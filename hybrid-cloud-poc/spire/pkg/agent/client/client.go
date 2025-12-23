package client

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"encoding/asn1"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"

	"github.com/sirupsen/logrus"
	"github.com/spiffe/go-spiffe/v2/spiffeid"
	agentv1 "github.com/spiffe/spire-api-sdk/proto/spire/api/server/agent/v1"
	bundlev1 "github.com/spiffe/spire-api-sdk/proto/spire/api/server/bundle/v1"
	entryv1 "github.com/spiffe/spire-api-sdk/proto/spire/api/server/entry/v1"
	svidv1 "github.com/spiffe/spire-api-sdk/proto/spire/api/server/svid/v1"
	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
	"github.com/spiffe/spire/pkg/agent/tpmplugin"
	"github.com/spiffe/spire/pkg/common/bundleutil"
	"github.com/spiffe/spire/pkg/common/fflag"
	"github.com/spiffe/spire/pkg/common/telemetry"
	"github.com/spiffe/spire/pkg/common/tlspolicy"
	"github.com/spiffe/spire/proto/spire/common"
	"github.com/spiffe/spire/pkg/agent/catalog"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

var (
	ErrUnableToGetStream = errors.New("unable to get a stream")

	entryOutputMask = &types.EntryMask{
		SpiffeId:       true,
		Selectors:      true,
		FederatesWith:  true,
		Admin:          true,
		Downstream:     true,
		RevisionNumber: true,
		StoreSvid:      true,
		Hint:           true,
		CreatedAt:      true,
	}
)

const rpcTimeout = 30 * time.Second

// Unified-Identity: Hardware Integration & Delegated Certification
type X509SVID struct {
	CertChain     []byte
	ExpiresAt     int64
	AttestedClaims []*types.AttestedClaims // AttestedClaims from server response
}

type JWTSVID struct {
	Token     string
	IssuedAt  time.Time
	ExpiresAt time.Time
}

type SyncStats struct {
	Entries SyncEntriesStats
	Bundles SyncBundlesStats
}

type SyncEntriesStats struct {
	Total   int
	Missing int
	Stale   int
	Dropped int
}

type SyncBundlesStats struct {
	Total int
}

type Client interface {
	FetchUpdates(ctx context.Context) (*Update, error)
	SyncUpdates(ctx context.Context, cachedEntries map[string]*common.RegistrationEntry, cachedBundles map[string]*common.Bundle) (SyncStats, error)
	RenewSVID(ctx context.Context, csr []byte) (*X509SVID, error)
	NewX509SVIDs(ctx context.Context, csrs map[string][]byte) (map[string]*X509SVID, error)
	NewJWTSVID(ctx context.Context, entryID string, audience []string) (*JWTSVID, error)

	// Release releases any resources that were held by this Client, if any.
	Release()
}

// Config holds a client configuration
type Config struct {
	Addr        string
	Log         logrus.FieldLogger
	TrustDomain spiffeid.TrustDomain
	// KeysAndBundle is a callback that must return the keys and bundle used by the client
	// to connect via mTLS to Addr.
	KeysAndBundle func() ([]*x509.Certificate, crypto.Signer, []*x509.Certificate)

	// RotMtx is used to prevent the creation of new connections during SVID rotations
	RotMtx *sync.RWMutex

	// TLSPolicy determines the post-quantum-safe policy to apply to all TLS connections.
	TLSPolicy tlspolicy.Policy

	Catalog catalog.Catalog
}

type client struct {
	c           *Config
	connections *nodeConn
	m           sync.Mutex

	// dialOpts optionally sets gRPC dial options
	dialOpts []grpc.DialOption

	Catalog catalog.Catalog

	tpmPlugin *tpmplugin.TPMPluginGateway
}

// New creates a new client struct with the configuration provided
func New(c *Config) Client {
	return newClient(c)
}

func newClient(c *Config) *client {
	cl := &client{
		c:       c,
		Catalog: c.Catalog,
	}

	// Unified-Identity: Initialize TPM plugin client for mTLS signing if needed
	if fflag.IsSet(fflag.FlagUnifiedIdentity) {
		pluginPath := os.Getenv("TPM_PLUGIN_CLI_PATH")
		if pluginPath == "" {
			possiblePaths := []string{
				"/tmp/spire-data/tpm-plugin/tpm_plugin_cli.py",
				filepath.Join(os.Getenv("HOME"), "AegisSovereignAI/hybrid-cloud-poc/tpm-plugin/tpm_plugin_cli.py"),
			}
			for _, path := range possiblePaths {
				if _, err := os.Stat(path); err == nil {
					pluginPath = path
					break
				}
			}
		}

		if pluginPath != "" {
			tpmPluginEndpoint := os.Getenv("TPM_PLUGIN_ENDPOINT")
			if tpmPluginEndpoint == "" {
				tpmPluginEndpoint = "unix:///tmp/spire-data/tpm-plugin/tpm-plugin.sock"
			}
			cl.tpmPlugin = tpmplugin.NewTPMPluginGateway(pluginPath, "", tpmPluginEndpoint, c.Log)
		}
	}

	return cl
}

func (c *client) FetchUpdates(ctx context.Context) (*Update, error) {
	c.c.RotMtx.RLock()
	defer c.c.RotMtx.RUnlock()

	ctx, cancel := context.WithTimeout(ctx, rpcTimeout)
	defer cancel()

	protoEntries, err := c.fetchEntries(ctx)
	if err != nil {
		return nil, err
	}

	regEntries := make(map[string]*common.RegistrationEntry)
	federatesWith := make(map[string]bool)
	for _, e := range protoEntries {
		entry, err := slicedEntryFromProto(e)
		if err != nil {
			c.c.Log.WithFields(logrus.Fields{
				telemetry.RegistrationID: e.Id,
				telemetry.SPIFFEID:       e.SpiffeId,
				telemetry.Selectors:      e.Selectors,
				telemetry.Error:          err.Error(),
			}).Warn("Received malformed entry from SPIRE server; are the server and agent versions compatible?")
			continue
		}

		// Get all federated trust domains
		for _, td := range entry.FederatesWith {
			federatesWith[td] = true
		}
		regEntries[entry.EntryId] = entry
	}

	keys := make([]string, 0, len(federatesWith))
	for key := range federatesWith {
		keys = append(keys, key)
	}

	protoBundles, err := c.fetchBundles(ctx, keys)
	if err != nil {
		return nil, err
	}

	bundles := make(map[string]*common.Bundle)
	for _, b := range protoBundles {
		bundle, err := bundleutil.CommonBundleFromProto(b)
		if err != nil {
			c.c.Log.WithError(err).Warn("Received malformed bundle from SPIRE server; are the server and agent versions compatible?")
			continue
		}
		bundles[bundle.TrustDomainId] = bundle
	}

	return &Update{
		Entries: regEntries,
		Bundles: bundles,
	}, nil
}

func (c *client) SyncUpdates(ctx context.Context, cachedEntries map[string]*common.RegistrationEntry, cachedBundles map[string]*common.Bundle) (SyncStats, error) {
	switch {
	case cachedEntries == nil:
		return SyncStats{}, errors.New("non-nil cached entries map is required")
	case cachedBundles == nil:
		return SyncStats{}, errors.New("non-nil cached bundles map is required")
	}

	c.c.RotMtx.RLock()
	defer c.c.RotMtx.RUnlock()

	ctx, cancel := context.WithTimeout(ctx, rpcTimeout)
	defer cancel()

	entriesStats, err := c.syncEntries(ctx, cachedEntries)
	if err != nil {
		return SyncStats{}, err
	}

	federatedTrustDomains := make(stringSet)
	for _, entry := range cachedEntries {
		for _, federatesWith := range entry.FederatesWith {
			federatedTrustDomains.Add(federatesWith)
		}
	}

	protoBundles, err := c.fetchBundles(ctx, federatedTrustDomains.Sorted())
	if err != nil {
		return SyncStats{}, err
	}

	for k := range cachedBundles {
		delete(cachedBundles, k)
	}

	for _, b := range protoBundles {
		bundle, err := bundleutil.CommonBundleFromProto(b)
		if err != nil {
			c.c.Log.WithError(err).Warn("Received malformed bundle from SPIRE server; are the server and agent versions compatible?")
			continue
		}
		cachedBundles[bundle.TrustDomainId] = bundle
	}

	return SyncStats{
		Entries: entriesStats,
		Bundles: SyncBundlesStats{
			Total: len(cachedBundles),
		},
	}, nil
}

// Unified-Identity: Hardware Integration & Delegated Certification
// Interface: SPIRE Agent → SPIRE Server
// Status: ✅ Existing (Standard SPIRE) - Extended with SovereignAttestation
// Transport: mTLS over TCP
// Protocol: gRPC (Protobuf)
// Port: SPIRE Server port (typically 8081)
// RPC Method: RenewAgent(RenewAgentRequest) returns (RenewAgentResponse)
// Authentication: TLS client certificate authentication, SPIRE trust domain validation
func (c *client) RenewSVID(ctx context.Context, csr []byte) (*X509SVID, error) {
	ctx, cancel := context.WithTimeout(ctx, rpcTimeout)
	defer cancel()

	agentClient, connection, err := c.newAgentClient()
	if err != nil {
		return nil, err
	}
	defer connection.Release()

	params := &agentv1.AgentX509SVIDParams{
		Csr: csr,
	}

	// Unified-Identity: Request nonce from server before building SovereignAttestation
	// Step 2: SPIRE Agent Requests Nonce from SPIRE Server (per architecture doc)
	var nonce string
	if fflag.IsSet(fflag.FlagUnifiedIdentity) {
		// First, request a nonce from the server
		nonceResp, err := agentClient.RenewAgent(ctx, &agentv1.RenewAgentRequest{
			Params: &agentv1.AgentX509SVIDParams{
				Csr: csr,
				// No SovereignAttestation yet - this is the nonce request
			},
		})
		if err != nil {
			c.release(connection)
			c.withErrorFields(err).Error("Failed to request nonce from server")
			return nil, fmt.Errorf("failed to request nonce from server: %w", err)
		}

		// Extract nonce from response (hex-encoded, 64 characters)
		// Step 2: SPIRE Server returns nonce in RenewAgentResponse.challenge_nonce
		challengeNonceBytes := nonceResp.GetChallengeNonce()
		if len(challengeNonceBytes) > 0 {
			nonce = hex.EncodeToString(challengeNonceBytes)
			c.c.Log.WithField("nonce_length", len(nonce)).Info("Unified-Identity: Received nonce from SPIRE Server")
		} else {
			// Fallback: generate nonce locally if server doesn't provide one
			nonceBytes := make([]byte, 32)
			if _, err := rand.Read(nonceBytes); err != nil {
				c.c.Log.WithError(err).Warn("Unified-Identity: Failed to generate nonce, using stub data")
				params.SovereignAttestation = BuildSovereignAttestationStub()
			} else {
				nonce = hex.EncodeToString(nonceBytes)
				c.c.Log.Warn("Unified-Identity: Server did not provide nonce, using locally generated nonce (fallback)")
			}
		}

		// Step 3-7: Build SovereignAttestation with nonce from server
		if nonce != "" {
			if collector, ok := c.c.Catalog.GetCollector(); ok {
				c.c.Log.Debug("Unified-Identity: Collecting sovereign attestation data via plugin for renewal")
				sa, err := collector.CollectSovereignAttestation(ctx, nonce)
				if err != nil {
					return nil, fmt.Errorf("failed to collect sovereign attestation for renewal: %w", err)
				}
				params.SovereignAttestation = sa
			} else {
				c.c.Log.Warn("Unified-Identity: Collector plugin not found during renewal, falling back to stub data (deprecated)")
				params.SovereignAttestation = BuildSovereignAttestationStub()
			}
		}
	}

	// Step 8: Send attestation request with SovereignAttestation
	resp, err := agentClient.RenewAgent(ctx, &agentv1.RenewAgentRequest{
		Params: params,
	})
	if err != nil {
		c.release(connection)
		c.withErrorFields(err).Error("Failed to renew agent")
		return nil, fmt.Errorf("failed to renew agent: %w", err)
	}

	var certChain []byte
	for _, cert := range resp.Svid.CertChain {
		certChain = append(certChain, cert...)
	}
	if len(resp.AttestedClaims) > 0 {
		claim := resp.AttestedClaims[0]
		c.c.Log.WithFields(logrus.Fields{
			"geolocation": claim.Geolocation,
		}).Info("Unified-Identity: Received AttestedClaims for agent SVID")
	}

	// Unified-Identity: Dump agent SVID details to logs
	if len(resp.Svid.CertChain) > 0 {
		cert, err := x509.ParseCertificate(resp.Svid.CertChain[0])
		if err == nil {
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

			// Unified-Identity: Log unified agent SVID with formatted, readable output
			c.c.Log.WithFields(logrus.Fields{
				"spiffe_id":     spiffeID,
				"serial_number": cert.SerialNumber.String(),
				"not_before":    cert.NotBefore.Format(time.RFC3339),
				"not_after":     cert.NotAfter.Format(time.RFC3339),
			}).Info("Unified-Identity: Agent Unified SVID renewed")

			// Log certificate PEM separately for readability
			c.c.Log.WithFields(logrus.Fields{
				"spiffe_id": spiffeID,
				"cert_pem":  string(certPEM),
			}).Info("Unified-Identity: Agent SVID Certificate (PEM)")

			// Log Unified Identity claims in formatted JSON if present
			if len(unifiedIdentityExt) > 0 {
				var claimsJSON map[string]interface{}
				if err := json.Unmarshal(unifiedIdentityExt, &claimsJSON); err == nil {
					// Format JSON for readable output
					claimsFormatted, _ := json.MarshalIndent(claimsJSON, "", "  ")
					// Log claims as a multi-line formatted message
					c.c.Log.WithFields(logrus.Fields{
						"spiffe_id": spiffeID,
					}).Infof("Unified-Identity: Agent SVID Unified Identity Claims:\n%s", string(claimsFormatted))
				} else {
					// Fallback if JSON parsing fails
					c.c.Log.WithFields(logrus.Fields{
						"spiffe_id":        spiffeID,
						"claims_raw":       string(unifiedIdentityExt),
					}).Warn("Unified-Identity: Agent SVID claims (raw, JSON parse failed)")
				}
			}
		}
	}

	return &X509SVID{
		CertChain:      certChain,
		ExpiresAt:      resp.Svid.ExpiresAt,
		AttestedClaims: resp.AttestedClaims,
	}, nil
}

func (c *client) NewX509SVIDs(ctx context.Context, csrs map[string][]byte) (map[string]*X509SVID, error) {
	c.c.RotMtx.RLock()
	defer c.c.RotMtx.RUnlock()

	ctx, cancel := context.WithTimeout(ctx, rpcTimeout)
	defer cancel()

	svids := make(map[string]*X509SVID)
	var params []*svidv1.NewX509SVIDParams
	for entryID, csr := range csrs {
		param := &svidv1.NewX509SVIDParams{
			EntryId: entryID,
			Csr:     csr,
		}
		
		// Unified-Identity: Add SovereignAttestation if feature flag is enabled
		if fflag.IsSet(fflag.FlagUnifiedIdentity) {
			if collector, ok := c.c.Catalog.GetCollector(); ok {
				c.c.Log.Debug("Unified-Identity: Collecting sovereign attestation data via plugin for workload")
				sa, err := collector.CollectSovereignAttestation(ctx, "") // No nonce for workload SVID request
				if err != nil {
					return nil, fmt.Errorf("failed to collect sovereign attestation for workload: %w", err)
				}
				param.SovereignAttestation = sa
			} else {
				c.c.Log.Warn("Unified-Identity: Collector plugin not found for workload, falling back to stub data (deprecated)")
				param.SovereignAttestation = BuildSovereignAttestationStub()
			}
		}
		
		params = append(params, param)
	}

	protoResults, err := c.fetchSVIDs(ctx, params)
	if err != nil {
		return nil, err
	}

	for i, result := range protoResults {
		entryID := params[i].EntryId
		if result == nil || result.Svid == nil {
			c.c.Log.WithField(telemetry.RegistrationID, entryID).Debug("Entry not found")
			continue
		}
		var certChain []byte
		for _, cert := range result.Svid.CertChain {
			certChain = append(certChain, cert...)
		}

		// Unified-Identity: Include AttestedClaims from server response
		svids[entryID] = &X509SVID{
			CertChain:     certChain,
			ExpiresAt:     result.Svid.ExpiresAt,
			AttestedClaims: result.AttestedClaims,
		}
	}

	return svids, nil
}

func (c *client) NewJWTSVID(ctx context.Context, entryID string, audience []string) (*JWTSVID, error) {
	c.c.RotMtx.RLock()
	defer c.c.RotMtx.RUnlock()

	ctx, cancel := context.WithTimeout(ctx, rpcTimeout)
	defer cancel()

	svidClient, connection, err := c.newSVIDClient()
	if err != nil {
		return nil, err
	}
	defer connection.Release()

	resp, err := svidClient.NewJWTSVID(ctx, &svidv1.NewJWTSVIDRequest{
		Audience: audience,
		EntryId:  entryID,
	})
	if err != nil {
		c.release(connection)
		c.withErrorFields(err).Error("Failed to fetch JWT SVID")
		return nil, fmt.Errorf("failed to fetch JWT SVID: %w", err)
	}

	svid := resp.Svid
	switch {
	case svid == nil:
		return nil, errors.New("JWTSVID response missing SVID")
	case svid.IssuedAt == 0:
		return nil, errors.New("JWTSVID missing issued at")
	case svid.ExpiresAt == 0:
		return nil, errors.New("JWTSVID missing expires at")
	case svid.IssuedAt > svid.ExpiresAt:
		return nil, errors.New("JWTSVID issued after it has expired")
	}

	return &JWTSVID{
		Token:     svid.Token,
		IssuedAt:  time.Unix(svid.IssuedAt, 0).UTC(),
		ExpiresAt: time.Unix(svid.ExpiresAt, 0).UTC(),
	}, nil
}

// Release the underlying connection.
func (c *client) Release() {
	c.release(nil)
}

func (c *client) release(conn *nodeConn) {
	c.m.Lock()
	defer c.m.Unlock()
	if c.connections != nil && (conn == nil || conn == c.connections) {
		c.connections.Release()
		c.connections = nil
	}
}

func (c *client) newServerGRPCClient() (*grpc.ClientConn, error) {
	// Unified-Identity: Only apply TLS restrictions (PreferPKCS1v15) AFTER attestation is complete
	// Initial attestation uses standard TLS (no client cert) and should have no restrictions
	// mTLS with TPM App Key (after attestation) needs TLS 1.2 and PKCS#1 v1.5
	
	// Check if we have a certificate chain (after attestation)
	chain, _, _ := c.c.KeysAndBundle()
	hasCertChain := len(chain) > 0
	
	tlsPolicy := c.c.TLSPolicy
	// Only enable PreferPKCS1v15 when we have a certificate chain (mTLS after attestation)
	if fflag.IsSet(fflag.FlagUnifiedIdentity) && c.tpmPlugin != nil && hasCertChain {
		// We have a certificate chain, so this is mTLS (after attestation)
		// Enable PreferPKCS1v15 to limit TLS to 1.2 and prefer PKCS#1 v1.5 signatures
		tlsPolicy.PreferPKCS1v15 = true
		c.c.Log.Info("Unified-Identity - Verification: Enabling PreferPKCS1v15 TLS policy for TPM App Key mTLS (after attestation)")
	} else if !hasCertChain {
		// No certificate chain yet - this is initial attestation (standard TLS, no restrictions)
		c.c.Log.Debug("Unified-Identity - Verification: Initial attestation (no cert chain), using standard TLS without restrictions")
	}

	return NewServerGRPCClient(ServerClientConfig{
		Address:     c.c.Addr,
		TrustDomain: c.c.TrustDomain,
		GetBundle: func() []*x509.Certificate {
			_, _, bundle := c.c.KeysAndBundle()
			return bundle
		},
		GetAgentCertificate: func() *tls.Certificate {
			chain, key, _ := c.c.KeysAndBundle()
			agentCert := &tls.Certificate{
				PrivateKey: key,
			}
			for _, cert := range chain {
				agentCert.Certificate = append(agentCert.Certificate, cert.Raw)
			}

			// Unified-Identity - Verification: Use TPM App Key for mTLS signing when enabled
			// Only use TPM App Key when we have a certificate chain (after attestation)
			if fflag.IsSet(fflag.FlagUnifiedIdentity) && c.tpmPlugin != nil && len(chain) > 0 {
				// Get App Key public key from TPM plugin
				appKeyResult, err := c.tpmPlugin.GenerateAppKey(false)
				if err != nil {
					c.c.Log.WithError(err).Warn("Unified-Identity - Verification: Failed to get App Key, using regular key for mTLS")
					return agentCert
				}

				if appKeyResult != nil && appKeyResult.AppKeyPublic != "" {
					// Create TPM signer with App Key
					tpmSigner, err := tpmplugin.NewTPMSigner(c.tpmPlugin, appKeyResult.AppKeyPublic, c.c.Log)
					if err != nil {
						c.c.Log.WithError(err).Warn("Unified-Identity - Verification: Failed to create TPM signer, using regular key for mTLS")
						return agentCert
					}

					// Replace private key with TPM signer
					agentCert.PrivateKey = tpmSigner
					c.c.Log.Info("Unified-Identity - Verification: Using TPM App Key for mTLS signing")
				}
			}

			return agentCert
		},
		TLSPolicy: tlsPolicy,
		dialOpts:  c.dialOpts,
	})
}

func (c *client) fetchEntries(ctx context.Context) ([]*types.Entry, error) {
	entryClient, connection, err := c.newEntryClient()
	if err != nil {
		return nil, err
	}
	defer connection.Release()

	resp, err := entryClient.GetAuthorizedEntries(ctx, &entryv1.GetAuthorizedEntriesRequest{
		OutputMask: entryOutputMask,
	})
	if err != nil {
		c.release(connection)
		c.withErrorFields(err).Error("Failed to fetch authorized entries")
		return nil, fmt.Errorf("failed to fetch authorized entries: %w", err)
	}

	return resp.Entries, err
}

func (c *client) syncEntries(ctx context.Context, cachedEntries map[string]*common.RegistrationEntry) (SyncEntriesStats, error) {
	entryClient, connection, err := c.newEntryClient()
	if err != nil {
		return SyncEntriesStats{}, err
	}
	defer connection.Release()

	stats, err := c.streamAndSyncEntries(ctx, entryClient, cachedEntries)
	if err != nil {
		c.release(connection)
		c.c.Log.WithError(err).Error("Failed to fetch authorized entries")
		return SyncEntriesStats{}, fmt.Errorf("failed to fetch authorized entries: %w", err)
	}

	return stats, nil
}

func entryIsStale(entry *common.RegistrationEntry, revisionNumber, revisionCreatedAt int64) bool {
	if entry.RevisionNumber != revisionNumber {
		return true
	}

	// TODO: remove in SPIRE 1.14
	if revisionCreatedAt == 0 {
		return false
	}

	// Verify that the CreatedAt of the entries match. If they are different, they are
	// completely different entries even if the revision number is the same.
	// This can happen for example if an entry is deleted and recreated with the
	// same entry id.
	if entry.CreatedAt != revisionCreatedAt {
		return true
	}

	return false
}

func (c *client) streamAndSyncEntries(ctx context.Context, entryClient entryv1.EntryClient, cachedEntries map[string]*common.RegistrationEntry) (stats SyncEntriesStats, err error) {
	// Build a set of all the entries to be removed. This set is initialized
	// with all entries currently known. As entries are synced down from the
	// server, they are removed from this set. If the sync is successful,
	// any entry that was not seen during sync, i.e., still remains a member
	// of this set, is removed from the cached entries.
	toRemove := make(map[string]struct{})
	for _, entry := range cachedEntries {
		toRemove[entry.EntryId] = struct{}{}
	}
	defer func() {
		if err == nil {
			stats.Dropped = len(toRemove)
			for id := range toRemove {
				delete(cachedEntries, id)
			}
			stats.Total = len(cachedEntries)
		}
	}()

	// needFull tracks the entry IDs of entries that are either not cached, or
	// that have been determined to be stale (based on revision number
	// comparison)
	var needFull []string

	// processEntryRevisions determines what needs to be synced down based
	// on entry revisions.
	processEntryRevisions := func(entryRevisions []*entryv1.EntryRevision) {
		for _, entryRevision := range entryRevisions {
			if entryRevision.Id == "" || entryRevision.RevisionNumber < 0 {
				c.c.Log.WithFields(logrus.Fields{
					telemetry.RegistrationID: entryRevision.Id,
					telemetry.RevisionNumber: entryRevision.RevisionNumber,
				}).Warn("Received malformed entry revision from SPIRE server; are the server and agent versions compatible?")
				continue
			}

			// The entry is still authorized for this agent. Don't remove it.
			delete(toRemove, entryRevision.Id)

			// If entry is either not cached or is stale, record the ID so
			// the full entry can be requested after syncing down all
			// entry revisions.
			if cachedEntry, ok := cachedEntries[entryRevision.Id]; !ok || entryIsStale(cachedEntry, entryRevision.GetRevisionNumber(), entryRevision.GetCreatedAt()) {
				needFull = append(needFull, entryRevision.Id)
			}
		}
	}

	// processServerEntries updates the cached entries
	processServerEntries := func(serverEntries []*types.Entry) {
		for _, serverEntry := range serverEntries {
			entry, err := slicedEntryFromProto(serverEntry)
			if err != nil {
				c.c.Log.WithFields(logrus.Fields{
					telemetry.RegistrationID: serverEntry.Id,
					telemetry.RevisionNumber: serverEntry.RevisionNumber,
					telemetry.SPIFFEID:       serverEntry.SpiffeId,
					telemetry.Selectors:      serverEntry.Selectors,
					telemetry.Error:          err.Error(),
				}).Warn("Received malformed entry from SPIRE server; are the server and agent versions compatible?")
				continue
			}

			// The entry is still authorized for this agent. Don't remove it.
			delete(toRemove, entry.EntryId)

			cachedEntry, ok := cachedEntries[entry.EntryId]
			switch {
			case !ok:
				stats.Missing++
			case entryIsStale(cachedEntry, entry.GetRevisionNumber(), entry.GetCreatedAt()):
				stats.Stale++
			}

			// Update the cached entry
			cachedEntries[entry.EntryId] = entry
		}
	}

	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	stream, err := entryClient.SyncAuthorizedEntries(ctx)
	if err != nil {
		return SyncEntriesStats{}, err
	}

	if err := stream.Send(&entryv1.SyncAuthorizedEntriesRequest{
		OutputMask: entryOutputMask,
	}); err != nil {
		return SyncEntriesStats{}, err
	}

	resp, err := stream.Recv()
	if err != nil {
		return SyncEntriesStats{}, err
	}

	// If the first response does not contain entry revisions then it contains
	// the complete list of authorized entries.
	if len(resp.EntryRevisions) == 0 {
		processServerEntries(resp.Entries)
		return stats, nil
	}

	// Assume that the page size is the size of the revisions in the first
	// response from the server.
	pageSize := len(resp.EntryRevisions)

	// Receive the rest of the entry revisions
	processEntryRevisions(resp.EntryRevisions)
	for resp.More {
		resp, err = stream.Recv()
		if err != nil {
			return SyncEntriesStats{}, fmt.Errorf("failed to receive entry revision page from server: %w", err)
		}
		if len(resp.Entries) > 0 {
			return SyncEntriesStats{}, errors.New("unexpected entry in response receiving entry revisions")
		}
		processEntryRevisions(resp.EntryRevisions)
	}

	// Presort the IDs. The server sorts the requested IDs as an optimization
	// for memory and CPU efficient lookups. Even though the server will sort
	// them, pre-sorting should reduce server CPU load (Go1.19+ implements
	// sorting via the PDQ algorithm, which performs well on pre-sorted data).
	sort.Strings(needFull)

	// Request the full entries for missing or stale entries one page at a
	// time using the assumed page size.
	for len(needFull) > 0 {
		// Request up to a page full of full entries
		n := min(len(needFull), pageSize)
		if err := stream.Send(&entryv1.SyncAuthorizedEntriesRequest{Ids: needFull[:n]}); err != nil {
			return SyncEntriesStats{}, err
		}
		needFull = needFull[n:]

		// Receive the full entries just requested. Even though the entries
		// SHOULD come back in a single response (since we matched the page
		// size of the server), handle the case where the server decides to
		// break them up into multiple pages.
		for {
			resp, err := stream.Recv()
			if err != nil {
				return SyncEntriesStats{}, fmt.Errorf("failed to receive entry revision page from server: %w", err)
			}
			if len(resp.EntryRevisions) != 0 {
				return SyncEntriesStats{}, errors.New("unexpected entry revisions in response while requesting entries")
			}
			processServerEntries(resp.Entries)
			if !resp.More {
				break
			}
		}
	}
	return stats, nil
}

func (c *client) fetchBundles(ctx context.Context, federatedBundles []string) ([]*types.Bundle, error) {
	bundleClient, connection, err := c.newBundleClient()
	if err != nil {
		return nil, err
	}
	defer connection.Release()

	var bundles []*types.Bundle

	// Get bundle
	bundle, err := bundleClient.GetBundle(ctx, &bundlev1.GetBundleRequest{})
	if err != nil {
		c.release(connection)
		c.withErrorFields(err).Error("Failed to fetch bundle")
		return nil, fmt.Errorf("failed to fetch bundle: %w", err)
	}
	bundles = append(bundles, bundle)

	for _, b := range federatedBundles {
		federatedTD, err := spiffeid.TrustDomainFromString(b)
		if err != nil {
			return nil, err
		}
		bundle, err := bundleClient.GetFederatedBundle(ctx, &bundlev1.GetFederatedBundleRequest{
			TrustDomain: federatedTD.Name(),
		})
		log := c.withErrorFields(err)
		switch status.Code(err) {
		case codes.OK:
			bundles = append(bundles, bundle)
		case codes.NotFound:
			log.WithField(telemetry.FederatedBundle, b).Warn("Federated bundle not found")
		default:
			log.WithField(telemetry.FederatedBundle, b).Error("Failed to fetch federated bundle")
			return nil, fmt.Errorf("failed to fetch federated bundle: %w", err)
		}
	}

	return bundles, nil
}

// Unified-Identity: Hardware Integration & Delegated Certification
// fetchSVIDsResult holds both the SVID and AttestedClaims from the server response
type fetchSVIDsResult struct {
	Svid           *types.X509SVID
	AttestedClaims []*types.AttestedClaims
}

func (c *client) fetchSVIDs(ctx context.Context, params []*svidv1.NewX509SVIDParams) ([]*fetchSVIDsResult, error) {
	svidClient, connection, err := c.newSVIDClient()
	if err != nil {
		return nil, err
	}
	defer connection.Release()

	resp, err := svidClient.BatchNewX509SVID(ctx, &svidv1.BatchNewX509SVIDRequest{
		Params: params,
	})
	if err != nil {
		c.release(connection)
		c.withErrorFields(err).Error("Failed to batch new X509 SVID(s)")
		return nil, fmt.Errorf("failed to batch new X509 SVID(s): %w", err)
	}

	okStatus := int32(codes.OK)
	var results []*fetchSVIDsResult
	for i, r := range resp.Results {
		if r.Status.Code != okStatus {
			c.c.Log.WithFields(logrus.Fields{
				telemetry.RegistrationID: params[i].EntryId,
				telemetry.Status:         r.Status.Code,
				telemetry.Error:          r.Status.Message,
			}).Warn("Failed to mint X509 SVID")
		}

		// Unified-Identity: Extract AttestedClaims from server response
		results = append(results, &fetchSVIDsResult{
			Svid:           r.Svid,
			AttestedClaims: r.AttestedClaims,
		})
	}

	return results, nil
}

// Unified-Identity: Build real SovereignAttestation using TPM plugin
// This function uses the real TPM plugin to generate App Keys, Quotes, and Certificates
// Falls back to stub data if TPM plugin is not available
// Unified-Identity: Build real SovereignAttestation using Collector plugin
func (c *client) BuildSovereignAttestation() *types.SovereignAttestation {
	if collector, ok := c.Catalog.GetCollector(); ok {
		sa, err := collector.CollectSovereignAttestation(context.Background(), "")
		if err == nil {
			return sa
		}
		c.c.Log.WithError(err).Warn("Unified-Identity: Failed to collect sovereign attestation via plugin, using stub data")
	} else {
		c.c.Log.Warn("Unified-Identity: Collector plugin not found, using stub data")
	}
	return BuildSovereignAttestationStub()
}


// Unified-Identity: Build stub SovereignAttestation
// This is used as a fallback when TPM is not available or TPM plugin fails
func BuildSovereignAttestationStub() *types.SovereignAttestation {
	// Stub TPM quote with fixed data (base64-encoded for testing)
	stubQuote := base64.StdEncoding.EncodeToString([]byte("stub-tpm-quote-phase3"))
	
	// Unified-Identity: Use valid PEM format for stub public key
	// This is a valid PEM-format EC public key for testing (generated with cryptography library)
	stubAppKeyPublic := `-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEmEfSIT6GJla8CK04AsF4bv9WyoFZ
BKTlYihT6v7QGy4hUq/djGG4il7vHmRm8nuOUzrQy7ViZhwhjNIRJH0hDg==
-----END PUBLIC KEY-----`
	
	return &types.SovereignAttestation{
		TpmSignedAttestation: stubQuote,
		AppKeyPublic:         stubAppKeyPublic,
		AppKeyCertificate:    []byte("stub-app-key-cert-phase3"), // Optional for testing
		ChallengeNonce:       "stub-nonce-phase-3",
		WorkloadCodeHash:     "stub-workload-code-hash-phase3",
	}
}

func (c *client) newEntryClient() (entryv1.EntryClient, *nodeConn, error) {
	conn, err := c.getOrOpenConn()
	if err != nil {
		return nil, nil, err
	}
	return entryv1.NewEntryClient(conn.Conn()), conn, nil
}

func (c *client) newBundleClient() (bundlev1.BundleClient, *nodeConn, error) {
	conn, err := c.getOrOpenConn()
	if err != nil {
		return nil, nil, err
	}
	return bundlev1.NewBundleClient(conn.Conn()), conn, nil
}

func (c *client) newSVIDClient() (svidv1.SVIDClient, *nodeConn, error) {
	conn, err := c.getOrOpenConn()
	if err != nil {
		return nil, nil, err
	}
	return svidv1.NewSVIDClient(conn.Conn()), conn, nil
}

func (c *client) newAgentClient() (agentv1.AgentClient, *nodeConn, error) {
	conn, err := c.getOrOpenConn()
	if err != nil {
		return nil, nil, err
	}
	return agentv1.NewAgentClient(conn.Conn()), conn, nil
}

func (c *client) getOrOpenConn() (*nodeConn, error) {
	c.m.Lock()
	defer c.m.Unlock()

	if c.connections == nil {
		conn, err := c.newServerGRPCClient()
		if err != nil {
			return nil, err
		}
		c.connections = newNodeConn(conn)
	}
	c.connections.AddRef()
	return c.connections, nil
}

type stringSet map[string]struct{}

func (ss stringSet) Add(s string) {
	ss[s] = struct{}{}
}

func (ss stringSet) Sorted() []string {
	sorted := make([]string, 0, len(ss))
	for s := range ss {
		sorted = append(sorted, s)
	}
	sort.Strings(sorted)
	return sorted
}

// withErrorFields add fields of gRPC call status in logger
func (c *client) withErrorFields(err error) logrus.FieldLogger {
	if err == nil {
		return c.c.Log
	}

	logger := c.c.Log.WithError(err)
	if s, ok := status.FromError(err); ok {
		logger = logger.WithFields(logrus.Fields{
			telemetry.StatusCode:    s.Code(),
			telemetry.StatusMessage: s.Message(),
		})
	}

	return logger
}
