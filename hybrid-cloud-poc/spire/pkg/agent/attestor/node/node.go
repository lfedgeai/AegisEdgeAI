package attestor

import (
	"context"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"encoding/asn1"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"time"

	"github.com/sirupsen/logrus"
	"github.com/spiffe/go-spiffe/v2/bundle/spiffebundle"
	"github.com/spiffe/go-spiffe/v2/spiffeid"
	agentv1 "github.com/spiffe/spire-api-sdk/proto/spire/api/server/agent/v1"
	bundlev1 "github.com/spiffe/spire-api-sdk/proto/spire/api/server/bundle/v1"
	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
	"github.com/spiffe/spire/pkg/agent/catalog"
	"github.com/spiffe/spire/pkg/agent/client"
	"github.com/spiffe/spire/pkg/agent/plugin/keymanager"
	"github.com/spiffe/spire/pkg/agent/plugin/nodeattestor"
	"github.com/spiffe/spire/pkg/agent/storage"
	"github.com/spiffe/spire/pkg/agent/tpmplugin"
	agentutil "github.com/spiffe/spire/pkg/agent/util"
	"github.com/spiffe/spire/pkg/common/bundleutil"
	"github.com/spiffe/spire/pkg/common/cryptoutil"
	"github.com/spiffe/spire/pkg/common/fflag"
	"github.com/spiffe/spire/pkg/common/idutil"
	"github.com/spiffe/spire/pkg/common/telemetry"
	telemetry_agent "github.com/spiffe/spire/pkg/common/telemetry/agent"
	telemetry_common "github.com/spiffe/spire/pkg/common/telemetry/common"
	"github.com/spiffe/spire/pkg/common/tlspolicy"
	"github.com/spiffe/spire/pkg/common/x509util"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
)

const (
	roundRobinServiceConfig = `{ "loadBalancingConfig": [ { "round_robin": {} } ] }`
)

type AttestationResult struct {
	SVID         []*x509.Certificate
	Key          keymanager.Key
	Bundle       *spiffebundle.Bundle
	Reattestable bool
}

type Attestor interface {
	Attest(ctx context.Context) (*AttestationResult, error)
}

type Config struct {
	Catalog              catalog.Catalog
	Metrics              telemetry.Metrics
	JoinToken            string
	TrustDomain          spiffeid.TrustDomain
	BootstrapTrustBundle []*x509.Certificate
	InsecureBootstrap    bool
	Storage              storage.Storage
	Log                  logrus.FieldLogger
	ServerAddress        string
	NodeAttestor         nodeattestor.NodeAttestor
	TLSPolicy            tlspolicy.Policy
}

type attestor struct {
	c *Config
}

func New(config *Config) Attestor {
	return &attestor{c: config}
}

func (a *attestor) Attest(ctx context.Context) (res *AttestationResult, err error) {
	log := a.c.Log

	bundle, err := a.loadBundle()
	if err != nil {
		return nil, err
	}
	if bundle == nil {
		log.Info("Bundle is not found")
	} else {
		log = log.WithField(telemetry.TrustDomainID, bundle.TrustDomain().IDString())
		log.Info("Bundle loaded")
	}

	svid, key, reattestable, err := a.loadSVID(ctx)
	if err != nil {
		return nil, err
	}

	switch {
	case svid == nil:
		log.Info("SVID is not found. Starting node attestation")
		svid, bundle, reattestable, err = a.newSVID(ctx, key, bundle)
		if err != nil {
			return nil, err
		}
		log.WithField(telemetry.SPIFFEID, svid[0].URIs[0].String()).WithField(telemetry.Reattestable, reattestable).Info("Node attestation was successful")
	case bundle == nil:
		// This is a bizarre case where we have an SVID but were unable to
		// load a bundle from the cache which suggests some tampering with the
		// cache on disk.
		return nil, errors.New("SVID loaded but no bundle in cache")
	default:
		log.WithField(telemetry.SPIFFEID, svid[0].URIs[0].String()).Info("SVID loaded")
	}

	return &AttestationResult{Bundle: bundle, SVID: svid, Key: key, Reattestable: reattestable}, nil
}

// Load the current SVID and key. The returned SVID is nil to indicate a new SVID should be created.
func (a *attestor) loadSVID(ctx context.Context) ([]*x509.Certificate, keymanager.Key, bool, error) {
	svidKM := keymanager.ForSVID(a.c.Catalog.GetKeyManager())
	allKeys, err := svidKM.GetKeys(ctx)
	if err != nil {
		return nil, nil, false, fmt.Errorf("unable to load private key: %w", err)
	}

	svid, reattestable := a.readSVIDFromDisk()
	svidKey, svidKeyExists := findKeyForSVID(allKeys, svid)
	svidExists := len(svid) > 0
	svidIsExpired := IsSVIDExpired(svid, time.Now)

	switch {
	case svidExists && svidKeyExists && !svidIsExpired:
		return svid, svidKey, reattestable, nil
	case svidExists && svidKeyExists && svidIsExpired:
		a.c.Log.WithField("expiry", svid[0].NotAfter).Warn("SVID key recovered, but SVID is expired. Generating new keypair")
	case svidExists && !svidKeyExists && len(allKeys) == 0:
		a.c.Log.Warn("SVID recovered, but no keys found. Generating new keypair")
	case svidExists && !svidKeyExists && len(allKeys) > 0:
		a.c.Log.Warn("SVID recovered, but no SVID key found. Generating new keypair")
	case !svidExists && len(allKeys) > 0:
		a.c.Log.Warn("Keys recovered, but no SVID found. Generating new keypair")
	default:
		// Neither private key nor SVID were found.
	}

	svidKey, err = svidKM.GenerateKey(ctx, svidKey)
	if err != nil {
		return nil, nil, false, fmt.Errorf("unable to generate private key: %w", err)
	}
	return nil, svidKey, reattestable, nil
}

// IsSVIDExpired returns true if the X.509 SVID provided is expired
func IsSVIDExpired(svid []*x509.Certificate, timeNow func() time.Time) bool {
	if len(svid) == 0 {
		return false
	}
	clockSkew := time.Second
	certExpiresAt := svid[0].NotAfter
	return timeNow().Add(clockSkew).Sub(certExpiresAt) >= 0
}

func (a *attestor) loadBundle() (*spiffebundle.Bundle, error) {
	bundle, err := a.c.Storage.LoadBundle()
	if errors.Is(err, storage.ErrNotCached) {
		if a.c.InsecureBootstrap {
			if len(a.c.BootstrapTrustBundle) > 0 {
				a.c.Log.Warn("Trust bundle will be ignored; performing insecure bootstrap")
			}
			return nil, nil
		}
		bundle = a.c.BootstrapTrustBundle
	} else if err != nil {
		return nil, fmt.Errorf("load bundle: %w", err)
	}

	if len(bundle) < 1 {
		return nil, errors.New("load bundle: no certs in bundle")
	}

	return spiffebundle.FromX509Authorities(a.c.TrustDomain, bundle), nil
}

func (a *attestor) getBundle(ctx context.Context, conn *grpc.ClientConn) (*spiffebundle.Bundle, error) {
	updatedBundle, err := bundlev1.NewBundleClient(conn).GetBundle(ctx, &bundlev1.GetBundleRequest{})
	if err != nil {
		return nil, fmt.Errorf("failed to get updated bundle %w", err)
	}

	b, err := bundleutil.CommonBundleFromProto(updatedBundle)
	if err != nil {
		return nil, fmt.Errorf("failed to parse trust domain bundle: %w", err)
	}

	bundle, err := bundleutil.SPIFFEBundleFromProto(b)
	if err != nil {
		return nil, fmt.Errorf("invalid trust domain bundle: %w", err)
	}

	return bundle, err
}

func (a *attestor) getSVID(ctx context.Context, conn *grpc.ClientConn, csr []byte, attestor nodeattestor.NodeAttestor) ([]*x509.Certificate, bool, error) {
	// make sure all the streams are cancelled if something goes awry
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	stream := &ServerStream{
		Client:  agentv1.NewAgentClient(conn),
		Csr:     csr,
		Log:     a.c.Log,
		Catalog: a.c.Catalog,
	}

	if err := attestor.Attest(ctx, stream); err != nil {
		return nil, false, err
	}

	return stream.SVID, stream.Reattestable, nil
}

// Read agent SVID from data dir. If an error is encountered, it will be logged and `nil`
// will be returned.
func (a *attestor) readSVIDFromDisk() ([]*x509.Certificate, bool) {
	svid, reattestable, err := a.c.Storage.LoadSVID()
	if errors.Is(err, storage.ErrNotCached) {
		a.c.Log.Debug("No pre-existing agent SVID found. Will perform node attestation")
		return nil, false
	} else if err != nil {
		a.c.Log.WithError(err).Warn("Could not get agent SVID from path")
	}
	return svid, reattestable
}

// newSVID obtains an agent svid for the given private key by performing node attesatation. The bundle is
// necessary in order to validate the SPIRE server we are attesting to. Returns the SVID and an updated bundle.
func (a *attestor) newSVID(ctx context.Context, key keymanager.Key, bundle *spiffebundle.Bundle) (_ []*x509.Certificate, _ *spiffebundle.Bundle, _ bool, err error) {
	counter := telemetry_agent.StartNodeAttestorNewSVIDCall(a.c.Metrics)
	defer counter.Done(&err)
	telemetry_common.AddAttestorType(counter, a.c.NodeAttestor.Name())

	conn, err := a.serverConn(bundle)
	if err != nil {
		return nil, nil, false, fmt.Errorf("create attestation client: %w", err)
	}
	defer conn.Close()

	// Unified-Identity - Verification: Use TPM App Key for CSR when enabled
	csr, signer, err := agentutil.MakeCSRForAttestation(key, a.c.Log)
	if err != nil {
		return nil, nil, false, fmt.Errorf("failed to generate CSR for attestation: %w", err)
	}
	
	// Note: The signer used for CSR creation may be a TPM signer or regular key
	// The certificate issued by the server will contain the public key from the CSR
	// For mTLS, we use the TPM signer in GetAgentCertificate callback (already implemented)
	// For State storage, we keep the regular key (TPM signer doesn't implement keymanager.Key)
	if _, ok := signer.(*tpmplugin.TPMSigner); ok {
		a.c.Log.Info("Unified-Identity - Verification: CSR created with TPM App Key, certificate will contain TPM App Key public key")
	}

	newSVID, reattestable, err := a.getSVID(ctx, conn, csr, a.c.NodeAttestor)
	if err != nil {
		return nil, nil, false, err
	}

	newBundle, err := a.getBundle(ctx, conn)
	if err != nil {
		return nil, nil, false, fmt.Errorf("failed to get updated bundle: %w", err)
	}

	return newSVID, newBundle, reattestable, nil
}

func (a *attestor) serverConn(bundle *spiffebundle.Bundle) (*grpc.ClientConn, error) {
	if bundle != nil {
		// Unified-Identity: Don't enable PreferPKCS1v15 for initial attestation connection
		// The attestation connection uses regular TLS (not mTLS), so we don't need PKCS#1 v1.5
		// PreferPKCS1v15 should only be enabled for mTLS connections where the agent presents
		// a certificate signed with the TPM App Key
		tlsPolicy := a.c.TLSPolicy
		// Note: We intentionally do NOT set PreferPKCS1v15 here for attestation
		// This allows the server certificate to use any compatible signature algorithm
		
		return client.NewServerGRPCClient(client.ServerClientConfig{
			Address:     a.c.ServerAddress,
			TrustDomain: a.c.TrustDomain,
			GetBundle:   bundle.X509Authorities,
			TLSPolicy:   tlsPolicy,
		})
	}

	if !a.c.InsecureBootstrap {
		// We shouldn't get here since loadBundle() should fail if the bundle
		// is empty, but just in case...
		return nil, errors.New("no bundle and not doing insecure bootstrap")
	}

	// Insecure bootstrapping. Do not verify the server chain but rather do a
	// simple, soft verification that the server URI matches the expected
	// SPIFFE ID. This is not a security feature but rather a check that we've
	// reached what appears to be the right trust domain server.
	tlsConfig := &tls.Config{
		InsecureSkipVerify: true, //nolint: gosec // this is required in order to do non-hostname based verification
		VerifyPeerCertificate: func(rawCerts [][]byte, _ [][]*x509.Certificate) error {
			a.c.Log.Warn("Insecure bootstrap enabled; skipping server certificate verification")
			if len(rawCerts) == 0 {
				// This is not really possible without a catastrophic bug
				// creeping into the TLS stack.
				return errors.New("server chain is unexpectedly empty")
			}

			expectedServerID, err := idutil.ServerID(a.c.TrustDomain)
			if err != nil {
				return err
			}

			serverCert, err := x509.ParseCertificate(rawCerts[0])
			if err != nil {
				return err
			}
			if len(serverCert.URIs) != 1 || serverCert.URIs[0].String() != expectedServerID.String() {
				return fmt.Errorf("expected server SPIFFE ID %q; got %q", expectedServerID, serverCert.URIs)
			}
			return nil
		},
	}

	return grpc.NewClient(
		a.c.ServerAddress,
		grpc.WithDefaultServiceConfig(roundRobinServiceConfig),
		grpc.WithDisableServiceConfig(),
		grpc.WithTransportCredentials(credentials.NewTLS(tlsConfig)),
	)
}

type ServerStream struct {
	Client       agentv1.AgentClient
	Csr          []byte
	Log          logrus.FieldLogger
	Catalog      catalog.Catalog
	SVID         []*x509.Certificate
	Reattestable bool
	stream       agentv1.Agent_AttestAgentClient
}

func (ss *ServerStream) SendAttestationData(ctx context.Context, attestationData nodeattestor.AttestationData) ([]byte, error) {
	x509Params := &agentv1.AgentX509SVIDParams{
		Csr: ss.Csr,
	}

	if fflag.IsSet(fflag.FlagUnifiedIdentity) {
		if c, ok := ss.Catalog.GetCollector(); ok {
			ss.Log.Debug("Unified-Identity: Collecting sovereign attestation data via plugin")
			
			// Generate a random nonce for the initial attestation
			// In a full implementation, this might come from a server challenge,
			// but for initial bootstrap/PoR, we generate a fresh nonce to bind the attestation.
			nonceBytes := make([]byte, 32)
			if _, err := rand.Read(nonceBytes); err != nil {
				return nil, fmt.Errorf("failed to generate nonce: %w", err)
			}
			nonce := hex.EncodeToString(nonceBytes)

			sa, err := c.CollectSovereignAttestation(ctx, nonce)
			if err != nil {
				return nil, fmt.Errorf("failed to collect sovereign attestation: %w", err)
			}
			x509Params.SovereignAttestation = sa
		} else {
			ss.Log.Warn("Unified-Identity: Collector plugin not found, falling back to stub data (deprecated)")
			x509Params.SovereignAttestation = client.BuildSovereignAttestationStub()
		}
	}

	return ss.sendRequest(ctx, &agentv1.AttestAgentRequest{
		Step: &agentv1.AttestAgentRequest_Params_{
			Params: &agentv1.AttestAgentRequest_Params{
				Data: &types.AttestationData{
					Type:    attestationData.Type,
					Payload: attestationData.Payload,
				},
				Params: x509Params,
			},
		},
	})
}

func (ss *ServerStream) SendChallengeResponse(ctx context.Context, response []byte) ([]byte, error) {
	return ss.sendRequest(ctx, &agentv1.AttestAgentRequest{
		Step: &agentv1.AttestAgentRequest_ChallengeResponse{
			ChallengeResponse: response,
		},
	})
}

func (ss *ServerStream) sendRequest(ctx context.Context, req *agentv1.AttestAgentRequest) ([]byte, error) {
	if ss.stream == nil {
		stream, err := ss.Client.AttestAgent(ctx)
		if err != nil {
			return nil, fmt.Errorf("could not open attestation stream to SPIRE server: %w", err)
		}
		ss.stream = stream
	}

	if err := ss.stream.Send(req); err != nil {
		return nil, fmt.Errorf("failed to send attestation request to SPIRE server: %w", err)
	}

	resp, err := ss.stream.Recv()
	if err != nil {
		return nil, fmt.Errorf("failed to receive attestation response: %w", err)
	}

	if challenge := resp.GetChallenge(); challenge != nil {
		return challenge, nil
	}

	svid, err := getSVIDFromAttestAgentResponse(resp)
	if err != nil {
		return nil, fmt.Errorf("failed to parse attestation response: %w", err)
	}

	if result := resp.GetResult(); result != nil {
		if claims := result.GetAttestedClaims(); len(claims) > 0 {
			claim := claims[0]
			ss.Log.WithFields(logrus.Fields{
				"geolocation": claim.Geolocation,
			}).Info("Unified-Identity - Verification: Received AttestedClaims during agent bootstrap")
		}
	}

	if err := ss.stream.CloseSend(); err != nil {
		ss.Log.WithError(err).Warn("failed to close stream send side")
	}

	ss.Reattestable = resp.GetResult().Reattestable
	ss.SVID = svid

	// Unified-Identity - Verification: Dump agent SVID details to logs
	if len(svid) > 0 {
		cert := svid[0]
		spiffeID := ""
		if len(cert.URIs) > 0 {
			spiffeID = cert.URIs[0].String()
		}

		// Extract Unified Identity extension if present
		unifiedIdentityOID := asn1.ObjectIdentifier{1, 3, 6, 1, 4, 1, 99999, 2}
		legacyOID := asn1.ObjectIdentifier{1, 3, 6, 1, 4, 1, 99999, 1}
		var unifiedIdentityExt []byte
		for _, ext := range cert.Extensions {
			if ext.Id.Equal(unifiedIdentityOID) || ext.Id.Equal(legacyOID) {
				unifiedIdentityExt = ext.Value
				break
			}
		}

		// Encode certificate to PEM
		certPEM := pem.EncodeToMemory(&pem.Block{
			Type:  "CERTIFICATE",
			Bytes: cert.Raw,
		})

		// Unified-Identity - Verification: Log unified agent SVID with formatted, readable output
		ss.Log.WithFields(logrus.Fields{
			"spiffe_id":     spiffeID,
			"serial_number": cert.SerialNumber.String(),
			"not_before":    cert.NotBefore.Format(time.RFC3339),
			"not_after":     cert.NotAfter.Format(time.RFC3339),
		}).Info("Unified-Identity - Verification: Agent Unified SVID received")

		// Log certificate PEM separately for readability
		ss.Log.WithFields(logrus.Fields{
			"spiffe_id": spiffeID,
			"cert_pem":  string(certPEM),
		}).Info("Unified-Identity - Verification: Agent SVID Certificate (PEM)")

		// Log Unified Identity claims in formatted JSON if present
		if len(unifiedIdentityExt) > 0 {
			var claimsJSON map[string]interface{}
			if err := json.Unmarshal(unifiedIdentityExt, &claimsJSON); err == nil {
				// Format JSON for readable output
				claimsFormatted, _ := json.MarshalIndent(claimsJSON, "", "  ")
				// Log claims as a multi-line formatted message
				ss.Log.WithFields(logrus.Fields{
					"spiffe_id": spiffeID,
				}).Infof("Unified-Identity - Verification: Agent SVID Unified Identity Claims:\n%s", string(claimsFormatted))
			} else {
				// Fallback if JSON parsing fails
				ss.Log.WithFields(logrus.Fields{
					"spiffe_id":        spiffeID,
					"claims_raw":       string(unifiedIdentityExt),
				}).Warn("Unified-Identity - Verification: Agent SVID claims (raw, JSON parse failed)")
			}
		}
	}

	return nil, nil
}

func findKeyForSVID(keys []keymanager.Key, svid []*x509.Certificate) (keymanager.Key, bool) {
	if len(svid) == 0 {
		return nil, false
	}
	for _, key := range keys {
		equal, err := cryptoutil.PublicKeyEqual(svid[0].PublicKey, key.Public())
		if err == nil && equal {
			return key, true
		}
	}
	return nil, false
}

func getSVIDFromAttestAgentResponse(r *agentv1.AttestAgentResponse) ([]*x509.Certificate, error) {
	if r.GetResult().Svid == nil {
		return nil, errors.New("attest response is missing SVID")
	}

	svid, err := x509util.RawCertsToCertificates(r.GetResult().Svid.CertChain)
	if err != nil {
		return nil, fmt.Errorf("invalid SVID cert chain: %w", err)
	}

	if len(svid) == 0 {
		return nil, errors.New("empty SVID cert chain")
	}

	return svid, nil
}
