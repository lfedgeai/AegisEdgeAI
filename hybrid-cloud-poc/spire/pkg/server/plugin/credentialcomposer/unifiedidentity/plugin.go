package unifiedidentity

import (
	"context"
	"crypto"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"sync"

	"github.com/hashicorp/hcl"
	"github.com/sirupsen/logrus"
	credentialcomposerv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/plugin/server/credentialcomposer/v1"
	configv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/service/common/config/v1"
	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
	"github.com/spiffe/spire/pkg/common/catalog"
	"github.com/spiffe/spire/pkg/common/pluginconf"
	"github.com/spiffe/spire/pkg/server/credtemplate"
	"github.com/spiffe/spire/pkg/server/keylime"
	"github.com/spiffe/spire/pkg/server/policy"
	"github.com/spiffe/spire/pkg/server/unifiedidentity"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func BuiltIn() catalog.BuiltIn {
	return builtIn(New())
}

func builtIn(p *Plugin) catalog.BuiltIn {
	return catalog.MakeBuiltIn("unifiedidentity",
		credentialcomposerv1.CredentialComposerPluginServer(p),
		configv1.ConfigServiceServer(p),
	)
}

type Configuration struct {
	KeylimeURL          string   `hcl:"keylime_url"`
	TLSCert             string   `hcl:"tls_cert"`
	TLSKey              string   `hcl:"tls_key"`
	CACert              string   `hcl:"ca_cert"`
	ServerName          string   `hcl:"server_name"`
	AllowedGeolocations []string `hcl:"allowed_geolocations"`
}

func buildConfig(coreConfig catalog.CoreConfig, hclText string, status *pluginconf.Status) *Configuration {
	newConfig := new(Configuration)
	if err := hcl.Decode(newConfig, hclText); err != nil {
		status.ReportError("plugin configuration is malformed")
		return nil
	}
	return newConfig
}

type Plugin struct {
	credentialcomposerv1.UnsafeCredentialComposerServer
	configv1.UnsafeConfigServer

	mu            sync.RWMutex
	keylimeClient *keylime.Client
	policyEngine  *policy.Engine
}

func New() *Plugin {
	return &Plugin{}
}

func (p *Plugin) ComposeServerX509CA(context.Context, *credentialcomposerv1.ComposeServerX509CARequest) (*credentialcomposerv1.ComposeServerX509CAResponse, error) {
	return nil, status.Error(codes.Unimplemented, "not implemented")
}

func (p *Plugin) ComposeServerX509SVID(context.Context, *credentialcomposerv1.ComposeServerX509SVIDRequest) (*credentialcomposerv1.ComposeServerX509SVIDResponse, error) {
	return nil, status.Error(codes.Unimplemented, "not implemented")
}

func (p *Plugin) Configure(ctx context.Context, req *configv1.ConfigureRequest) (*configv1.ConfigureResponse, error) {
	newConfig, _, err := pluginconf.Build(req, buildConfig)
	if err != nil {
		return nil, err
	}

	p.mu.Lock()
	defer p.mu.Unlock()

	if newConfig.KeylimeURL != "" {
		client, err := keylime.NewClient(keylime.Config{
			BaseURL:    newConfig.KeylimeURL,
			TLSCert:    newConfig.TLSCert,
			TLSKey:     newConfig.TLSKey,
			CACert:     newConfig.CACert,
			ServerName: newConfig.ServerName,
			Logger:     logrus.New(), // The client will wrap this with its own logger if needed
		})
		if err != nil {
			return nil, status.Errorf(codes.Internal, "failed to create Keylime client: %v", err)
		}
		p.keylimeClient = client
	}

	p.policyEngine = policy.NewEngine(policy.PolicyConfig{
		AllowedGeolocations: newConfig.AllowedGeolocations,
	})

	return &configv1.ConfigureResponse{}, nil
}

func (p *Plugin) Validate(ctx context.Context, req *configv1.ValidateRequest) (*configv1.ValidateResponse, error) {
	_, notes, err := pluginconf.Build(req, buildConfig)

	return &configv1.ValidateResponse{
		Valid: err == nil,
		Notes: notes,
	}, err
}

func (p *Plugin) ComposeAgentX509SVID(ctx context.Context, req *credentialcomposerv1.ComposeAgentX509SVIDRequest) (*credentialcomposerv1.ComposeAgentX509SVIDResponse, error) {
	if req.Attributes == nil {
		return nil, status.Error(codes.InvalidArgument, "request missing attributes")
	}

	attributes := req.Attributes
	// Debug logging
	logrus.Infof("Unified-Identity: ComposeAgentX509SVID called for %s", req.SpiffeId)
	
	claims, unifiedJSON, err := p.processSovereignAttestation(ctx, req.SpiffeId, req.PublicKey, unifiedidentity.KeySourceTPMApp, true)
	if err != nil {
		logrus.Errorf("Unified-Identity: processSovereignAttestation failed: %v", err)
		return nil, err
	}

	if claims != nil || len(unifiedJSON) > 0 {
		ext, err := credtemplate.AttestedClaimsExtension(claims, unifiedJSON)
		if err != nil {
			return nil, status.Errorf(codes.Internal, "failed to create AttestedClaims extension: %v", err)
		}
		if ext.Id != nil {
			attributes.ExtraExtensions = append(attributes.ExtraExtensions, &credentialcomposerv1.X509Extension{
				Oid:      ext.Id.String(),
				Value:    ext.Value,
				Critical: ext.Critical,
			})
		}
	}

	return &credentialcomposerv1.ComposeAgentX509SVIDResponse{
		Attributes: attributes,
	}, nil
}

func (p *Plugin) ComposeWorkloadX509SVID(ctx context.Context, req *credentialcomposerv1.ComposeWorkloadX509SVIDRequest) (*credentialcomposerv1.ComposeWorkloadX509SVIDResponse, error) {
	if req.Attributes == nil {
		return nil, status.Error(codes.InvalidArgument, "request missing attributes")
	}

	attributes := req.Attributes
	claims, unifiedJSON, err := p.processSovereignAttestation(ctx, req.SpiffeId, req.PublicKey, unifiedidentity.KeySourceWorkload, false)
	if err != nil {
		return nil, err
	}

	if claims != nil || len(unifiedJSON) > 0 {
		ext, err := credtemplate.AttestedClaimsExtension(claims, unifiedJSON)
		if err != nil {
			return nil, status.Errorf(codes.Internal, "failed to create AttestedClaims extension: %v", err)
		}
		if ext.Id != nil {
			attributes.ExtraExtensions = append(attributes.ExtraExtensions, &credentialcomposerv1.X509Extension{
				Oid:      ext.Id.String(),
				Value:    ext.Value,
				Critical: ext.Critical,
			})
		}
	}

	return &credentialcomposerv1.ComposeWorkloadX509SVIDResponse{
		Attributes: attributes,
	}, nil
}

func (p *Plugin) processSovereignAttestation(ctx context.Context, spiffeID string, publicKey []byte, keySource string, isAgent bool) (*types.AttestedClaims, []byte, error) {
	sa := unifiedidentity.FromSovereignAttestation(ctx)
	if sa == nil {
		logrus.Infof("Unified-Identity: SovereignAttestation is nil in context (falling back to legacy/empty)")
		// Fallback to legacy context claims if any
		claims, unifiedJSON := unifiedidentity.FromContext(ctx)
		return claims, unifiedJSON, nil
	}
	logrus.Infof("Unified-Identity: SovereignAttestation found in context for %s", spiffeID)
	logrus.Infof("Unified-Identity: SA Details: TpmAttestation len=%d, AppKeyCert len=%d", len(sa.TpmSignedAttestation), len(sa.AppKeyCertificate))

	p.mu.RLock()
	client := p.keylimeClient
    engine := p.policyEngine
	p.mu.RUnlock()

	// Workload SVIDs are handled locally for scalability; only agent SVIDs go to Keylime
	if !isAgent {
		logrus.Infof("Unified-Identity: Skipping Keylime verification for workload SVID (handled locally)")
		// Build local claims without Keylime verification
		claims := &types.AttestedClaims{}
		unifiedJSON, err := buildLocalWorkloadClaims(sa, spiffeID, keySource)
		if err != nil {
			return nil, nil, status.Errorf(codes.Internal, "failed to build local workload claims: %v", err)
		}
		return claims, unifiedJSON, nil
	}
	
	if client == nil {
		logrus.Infof("Unified-Identity: Keylime Client is nil - skipping verification")
		return nil, nil, nil
	}
    logrus.Infof("Unified-Identity: Proceeding to verify evidence with Keylime for agent SVID")
    
    // Debug: Inspect SovereignAttestation fields
    logrus.Infof("Unified-Identity: Debug Payload - Quote Length: %d", len(sa.TpmSignedAttestation))
    if len(sa.TpmSignedAttestation) > 50 {
         logrus.Infof("Unified-Identity: Debug Payload - Quote Preview: %s...", sa.TpmSignedAttestation[:50])
    } else {
         logrus.Infof("Unified-Identity: Debug Payload - Quote Full: %s", sa.TpmSignedAttestation)
    }
    logrus.Infof("Unified-Identity: Debug Payload - AppKeyPublic Length: %d", len(sa.AppKeyPublic))
    logrus.Infof("Unified-Identity: Debug Payload - AppKeyCertificate Length: %d", len(sa.AppKeyCertificate))
    logrus.Infof("Unified-Identity: Debug Payload - ChallengeNonce: %s", sa.ChallengeNonce)
    logrus.Infof("Unified-Identity: Debug Payload - WorkloadCodeHash: %s", sa.WorkloadCodeHash)

	// Build Keylime request
	keylimeReq, err := keylime.BuildVerifyEvidenceRequest(&keylime.SovereignAttestationProto{
		TpmSignedAttestation: sa.TpmSignedAttestation,
		AppKeyPublic:         sa.AppKeyPublic,
		AppKeyCertificate:    sa.AppKeyCertificate,
		ChallengeNonce:       sa.ChallengeNonce,
		WorkloadCodeHash:     sa.WorkloadCodeHash,
	}, "")
	if err != nil {
		return nil, nil, status.Errorf(codes.Internal, "failed to build Keylime request: %v", err)
	}

	// Call Keylime Verifier
	keylimeClaims, err := client.VerifyEvidence(keylimeReq)
	if err != nil {
		return nil, nil, status.Errorf(codes.PermissionDenied, "keylime verification failed: %v", err)
	}

	// Evaluate policy
	if engine != nil {
		policyGeoStr := ""
		if keylimeClaims.Geolocation != nil {
			if keylimeClaims.Geolocation.Value != "" {
				policyGeoStr = fmt.Sprintf("%s:%s:%s", keylimeClaims.Geolocation.Type, keylimeClaims.Geolocation.SensorID, keylimeClaims.Geolocation.Value)
			} else {
				policyGeoStr = fmt.Sprintf("%s:%s", keylimeClaims.Geolocation.Type, keylimeClaims.Geolocation.SensorID)
			}
		}

		policyClaims := policy.ConvertKeylimeAttestedClaims(&policy.KeylimeAttestedClaims{
			Geolocation: policyGeoStr,
		})

		policyResult, err := engine.Evaluate(policyClaims)
		if err != nil {
			return nil, nil, status.Errorf(codes.Internal, "policy evaluation failed: %v", err)
		}

		if !policyResult.Allowed {
			return nil, nil, status.Errorf(codes.PermissionDenied, "policy evaluation failed: %s", policyResult.Reason)
		}
	}

	// Convert Geolocation object to protobuf Geolocation
	var protoGeo *types.Geolocation
	if keylimeClaims.Geolocation != nil {
		protoGeo = &types.Geolocation{
			Type:         keylimeClaims.Geolocation.Type,
			SensorId:     keylimeClaims.Geolocation.SensorID,
			Value:        keylimeClaims.Geolocation.Value,
			SensorImei:   keylimeClaims.Geolocation.SensorIMEI,
			SensorImsi:   keylimeClaims.Geolocation.SensorIMSI,
			SensorMsisdn: keylimeClaims.Geolocation.SensorMSISDN, // Task 2f: MSISDN from Keylime
		}
	}

	claims := &types.AttestedClaims{
		Geolocation: protoGeo,
	}

	// Build unified identity JSON
	var workloadKeyPEM string
	if keySource == unifiedidentity.KeySourceWorkload {
		parsedKey, err := x509.ParsePKIXPublicKey(publicKey)
		if err == nil {
			workloadKeyPEM, _ = publicKeyToPEM(parsedKey)
		}
	}

	unifiedJSON, err := unifiedidentity.BuildClaimsJSON(spiffeID, keySource, workloadKeyPEM, sa, claims)
	if err != nil {
		return nil, nil, status.Errorf(codes.Internal, "failed to build claims JSON: %v", err)
	}

	return claims, unifiedJSON, nil
}

// buildLocalWorkloadClaims builds claims for workload SVIDs locally without Keylime verification
func buildLocalWorkloadClaims(sa *types.SovereignAttestation, spiffeID string, keySource string) ([]byte, error) {
	// For workload SVIDs, we inherit the attestation evidence from the agent SVID
	// but don't send it to Keylime for verification (scalability)
	unifiedJSON, err := unifiedidentity.BuildClaimsJSON(spiffeID, keySource, "", sa, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to build workload claims JSON: %w", err)
	}
	return unifiedJSON, nil
}

func publicKeyToPEM(pub crypto.PublicKey) (string, error) {
	der, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		return "", err
	}
	block := &pem.Block{Type: "PUBLIC KEY", Bytes: der}
	return string(pem.EncodeToMemory(block)), nil
}

func (p *Plugin) ComposeWorkloadJWTSVID(context.Context, *credentialcomposerv1.ComposeWorkloadJWTSVIDRequest) (*credentialcomposerv1.ComposeWorkloadJWTSVIDResponse, error) {
	return nil, status.Error(codes.Unimplemented, "not implemented")
}
