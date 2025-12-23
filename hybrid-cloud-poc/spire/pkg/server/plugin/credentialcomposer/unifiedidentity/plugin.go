package unifiedidentity

	"context"
	"crypto"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"strings"
	"sync"

	"github.com/hashicorp/hcl"
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

	return catalog.MakeBuiltIn("unifiedidentity",
		credentialcomposerv1.CredentialComposerPluginServer(p),
		configv1.ConfigServiceServer(p),
	)
}

type Configuration struct {
	KeylimeURL          string   `hcl:"keylime_url"`
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
			BaseURL: newConfig.KeylimeURL,
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
	claims, unifiedJSON, err := p.processSovereignAttestation(ctx, req.SpiffeId, req.Csr, unifiedidentity.KeySourceTPMApp)
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

	return &credentialcomposerv1.ComposeAgentX509SVIDResponse{
		Attributes: attributes,
	}, nil
}

func (p *Plugin) ComposeWorkloadX509SVID(ctx context.Context, req *credentialcomposerv1.ComposeWorkloadX509SVIDRequest) (*credentialcomposerv1.ComposeWorkloadX509SVIDResponse, error) {
	if req.Attributes == nil {
		return nil, status.Error(codes.InvalidArgument, "request missing attributes")
	}

	attributes := req.Attributes
	claims, unifiedJSON, err := p.processSovereignAttestation(ctx, req.SpiffeId, req.Csr, unifiedidentity.KeySourceWorkload)
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

func (p *Plugin) processSovereignAttestation(ctx context.Context, spiffeID string, csr []byte, keySource string) (*types.AttestedClaims, []byte, error) {
	sa := unifiedidentity.FromSovereignAttestation(ctx)
	if sa == nil {
		// Fallback to legacy context claims if any
		claims, unifiedJSON := unifiedidentity.FromContext(ctx)
		return claims, unifiedJSON, nil
	}

	p.mu.RLock()
	client := p.keylimeClient
	engine := p.policyEngine
	p.mu.RUnlock()

	if client == nil {
		return nil, nil, nil
	}

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
			Type:       keylimeClaims.Geolocation.Type,
			SensorId:   keylimeClaims.Geolocation.SensorID,
			Value:      keylimeClaims.Geolocation.Value,
			SensorImei: keylimeClaims.Geolocation.SensorIMEI,
			SensorImsi: keylimeClaims.Geolocation.SensorIMSI,
		}
	}

	claims := &types.AttestedClaims{
		Geolocation: protoGeo,
	}

	// Build unified identity JSON
	var workloadKeyPEM string
	if keySource == unifiedidentity.KeySourceWorkload {
		parsedCsr, err := x509.ParseCertificateRequest(csr)
		if err == nil {
			workloadKeyPEM, _ = publicKeyToPEM(parsedCsr.PublicKey)
		}
	}

	unifiedJSON, err := unifiedidentity.BuildClaimsJSON(spiffeID, keySource, workloadKeyPEM, sa, claims)
	if err != nil {
		return nil, nil, status.Errorf(codes.Internal, "failed to build claims JSON: %v", err)
	}

	return claims, unifiedJSON, nil
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
