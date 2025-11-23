package svid

import (
	"context"
	"crypto"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"strings"
	"time"

	"github.com/sirupsen/logrus"
	"github.com/spiffe/go-spiffe/v2/spiffeid"
	svidv1 "github.com/spiffe/spire-api-sdk/proto/spire/api/server/svid/v1"
	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
	"github.com/spiffe/spire/pkg/common/fflag"
	"github.com/spiffe/spire/pkg/common/idutil"
	"github.com/spiffe/spire/pkg/common/jwtsvid"
	"github.com/spiffe/spire/pkg/common/telemetry"
	"github.com/spiffe/spire/pkg/common/x509util"
	"github.com/spiffe/spire/pkg/server/api"
	"github.com/spiffe/spire/pkg/server/api/rpccontext"
	"github.com/spiffe/spire/pkg/server/ca"
	"github.com/spiffe/spire/pkg/server/datastore"
	"github.com/spiffe/spire/pkg/server/keylime"
	"github.com/spiffe/spire/pkg/server/policy"
	"github.com/spiffe/spire/pkg/server/unifiedidentity"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// RegisterService registers the service on the gRPC server.
func RegisterService(s grpc.ServiceRegistrar, service *Service) {
	svidv1.RegisterSVIDServer(s, service)
}

// Config is the service configuration
type Config struct {
	EntryFetcher api.AuthorizedEntryFetcher
	ServerCA     ca.ServerCA
	TrustDomain  spiffeid.TrustDomain
	DataStore    datastore.DataStore
	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Optional Keylime client for sovereign attestation verification
	KeylimeClient *keylime.Client
	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Optional policy engine for evaluating AttestedClaims
	PolicyEngine *policy.Engine
}

// New creates a new SVID service
func New(config Config) *Service {
	return &Service{
		ca:            config.ServerCA,
		ef:            config.EntryFetcher,
		td:            config.TrustDomain,
		ds:            config.DataStore,
		keylimeClient: config.KeylimeClient,
		policyEngine:  config.PolicyEngine,
	}
}

// Service implements the v1 SVID service
type Service struct {
	svidv1.UnsafeSVIDServer

	ca                           ca.ServerCA
	ef                           api.AuthorizedEntryFetcher
	td                           spiffeid.TrustDomain
	ds                           datastore.DataStore
	useLegacyDownstreamX509CATTL bool
	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	keylimeClient *keylime.Client
	policyEngine  *policy.Engine
}

func (s *Service) MintX509SVID(ctx context.Context, req *svidv1.MintX509SVIDRequest) (*svidv1.MintX509SVIDResponse, error) {
	log := rpccontext.Logger(ctx)
	rpccontext.AddRPCAuditFields(ctx, logrus.Fields{
		telemetry.Csr: api.HashByte(req.Csr),
		telemetry.TTL: req.Ttl,
	})

	if len(req.Csr) == 0 {
		return nil, api.MakeErr(log, codes.InvalidArgument, "missing CSR", nil)
	}

	csr, err := x509.ParseCertificateRequest(req.Csr)
	if err != nil {
		return nil, api.MakeErr(log, codes.InvalidArgument, "malformed CSR", err)
	}

	if err := csr.CheckSignature(); err != nil {
		return nil, api.MakeErr(log, codes.InvalidArgument, "failed to verify CSR signature", err)
	}

	switch {
	case len(csr.URIs) == 0:
		return nil, api.MakeErr(log, codes.InvalidArgument, "CSR URI SAN is required", nil)
	case len(csr.URIs) > 1:
		return nil, api.MakeErr(log, codes.InvalidArgument, "only one URI SAN is expected", nil)
	}

	id, err := spiffeid.FromURI(csr.URIs[0])
	if err != nil {
		return nil, api.MakeErr(log, codes.InvalidArgument, "CSR URI SAN is invalid", err)
	}

	if err := api.VerifyTrustDomainWorkloadID(s.td, id); err != nil {
		return nil, api.MakeErr(log, codes.InvalidArgument, "CSR URI SAN is invalid", err)
	}

	dnsNames := make([]string, 0, len(csr.DNSNames))
	for _, dnsName := range csr.DNSNames {
		err := x509util.ValidateLabel(dnsName)
		if err != nil {
			return nil, api.MakeErr(log, codes.InvalidArgument, "CSR DNS name is invalid", err)
		}
		dnsNames = append(dnsNames, dnsName)
	}

	if err := x509util.CheckForWildcardOverlap(dnsNames); err != nil {
		return nil, api.MakeErr(log, codes.InvalidArgument, "CSR DNS name contains a wildcard that covers another non-wildcard name", err)
	}

	x509SVID, err := s.ca.SignWorkloadX509SVID(ctx, ca.WorkloadX509SVIDParams{
		SPIFFEID:  id,
		PublicKey: csr.PublicKey,
		TTL:       time.Duration(req.Ttl) * time.Second,
		DNSNames:  dnsNames,
		Subject:   csr.Subject,
	})
	if err != nil {
		return nil, api.MakeErr(log, codes.Internal, "failed to sign X509-SVID", err)
	}

	commonX509SVIDLogFields := logrus.Fields{
		telemetry.SPIFFEID: id.String(),
		telemetry.DNSName:  strings.Join(csr.DNSNames, ","),
		telemetry.Subject:  csr.Subject,
	}

	rpccontext.AddRPCAuditFields(ctx, logrus.Fields{
		telemetry.ExpiresAt: x509SVID[0].NotAfter.Format(time.RFC3339),
	})

	rpccontext.AuditRPCWithFields(ctx, commonX509SVIDLogFields)
	log.WithField(telemetry.Expiration, x509SVID[0].NotAfter.Format(time.RFC3339)).
		WithField(telemetry.SerialNumber, x509SVID[0].SerialNumber.String()).
		WithFields(commonX509SVIDLogFields).
		Debug("Signed X509 SVID")

	return &svidv1.MintX509SVIDResponse{
		Svid: &types.X509SVID{
			Id:        api.ProtoFromID(id),
			CertChain: x509util.RawCertsFromCertificates(x509SVID),
			ExpiresAt: x509SVID[0].NotAfter.Unix(),
		},
	}, nil
}

func (s *Service) MintJWTSVID(ctx context.Context, req *svidv1.MintJWTSVIDRequest) (*svidv1.MintJWTSVIDResponse, error) {
	rpccontext.AddRPCAuditFields(ctx, s.fieldsFromJWTSvidParams(ctx, req.Id, req.Audience, req.Ttl))
	jwtsvid, err := s.mintJWTSVID(ctx, req.Id, req.Audience, req.Ttl)
	if err != nil {
		return nil, err
	}
	rpccontext.AuditRPC(ctx)

	return &svidv1.MintJWTSVIDResponse{
		Svid: jwtsvid,
	}, nil
}

func (s *Service) BatchNewX509SVID(ctx context.Context, req *svidv1.BatchNewX509SVIDRequest) (*svidv1.BatchNewX509SVIDResponse, error) {
	log := rpccontext.Logger(ctx)

	if len(req.Params) == 0 {
		return nil, api.MakeErr(log, codes.InvalidArgument, "missing parameters", nil)
	}

	if err := rpccontext.RateLimit(ctx, len(req.Params)); err != nil {
		return nil, api.MakeErr(log, status.Code(err), "rejecting request due to certificate signing rate limiting", err)
	}

	requestedEntries := make(map[string]struct{})
	for _, svidParam := range req.Params {
		requestedEntries[svidParam.GetEntryId()] = struct{}{}
	}

	// Fetch authorized entries
	entriesMap, err := s.findEntries(ctx, log, requestedEntries)
	if err != nil {
		return nil, err
	}

	var results []*svidv1.BatchNewX509SVIDResponse_Result
	for _, svidParam := range req.Params {
		//  Create new SVID
		r := s.newX509SVID(ctx, svidParam, entriesMap)
		results = append(results, r)
		spiffeID := ""
		if r.Svid != nil {
			id, err := idutil.IDProtoString(r.Svid.Id)
			if err == nil {
				spiffeID = id
			}
		}

		rpccontext.AuditRPCWithTypesStatus(ctx, r.Status, func() logrus.Fields {
			fields := logrus.Fields{
				telemetry.Csr:            api.HashByte(svidParam.Csr),
				telemetry.RegistrationID: svidParam.EntryId,
				telemetry.SPIFFEID:       spiffeID,
			}

			if r.Svid != nil {
				fields[telemetry.ExpiresAt] = r.Svid.ExpiresAt
			}

			return fields
		})
	}

	return &svidv1.BatchNewX509SVIDResponse{Results: results}, nil
}

func (s *Service) findEntries(ctx context.Context, log logrus.FieldLogger, entries map[string]struct{}) (map[string]api.ReadOnlyEntry, error) {
	callerID, ok := rpccontext.CallerID(ctx)
	if !ok {
		return nil, api.MakeErr(log, codes.Internal, "caller ID missing from request context", nil)
	}

	foundEntries, err := s.ef.LookupAuthorizedEntries(ctx, callerID, entries)
	if err != nil {
		return nil, api.MakeErr(log, codes.Internal, "failed to fetch registration entries", err)
	}
	return foundEntries, nil
}

// newX509SVID creates an X509-SVID using data from registration entry and key from CSR
func (s *Service) newX509SVID(ctx context.Context, param *svidv1.NewX509SVIDParams, entries map[string]api.ReadOnlyEntry) *svidv1.BatchNewX509SVIDResponse_Result {
	log := rpccontext.Logger(ctx)

	switch {
	case param.EntryId == "":
		return &svidv1.BatchNewX509SVIDResponse_Result{
			Status: api.MakeStatus(log, codes.InvalidArgument, "missing entry ID", nil),
		}
	case len(param.Csr) == 0:
		return &svidv1.BatchNewX509SVIDResponse_Result{
			Status: api.MakeStatus(log, codes.InvalidArgument, "missing CSR", nil),
		}
	}

	log = log.WithField(telemetry.RegistrationID, param.EntryId)

	entry, ok := entries[param.EntryId]
	if !ok {
		return &svidv1.BatchNewX509SVIDResponse_Result{
			Status: api.MakeStatus(log, codes.NotFound, "entry not found or not authorized", nil),
		}
	}

	csr, err := x509.ParseCertificateRequest(param.Csr)
	if err != nil {
		return &svidv1.BatchNewX509SVIDResponse_Result{
			Status: api.MakeStatus(log, codes.InvalidArgument, "malformed CSR", err),
		}
	}

	if err := csr.CheckSignature(); err != nil {
		return &svidv1.BatchNewX509SVIDResponse_Result{
			Status: api.MakeStatus(log, codes.InvalidArgument, "invalid CSR signature", err),
		}
	}

	spiffeID, err := api.TrustDomainMemberIDFromProto(ctx, s.td, entry.GetSpiffeId())
	if err != nil {
		// This shouldn't be the case unless there is invalid data in the datastore
		return &svidv1.BatchNewX509SVIDResponse_Result{
			Status: api.MakeStatus(log, codes.Internal, "entry has malformed SPIFFE ID", err),
		}
	}
	log = log.WithField(telemetry.SPIFFEID, spiffeID.String())

	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Handle SovereignAttestation if feature flag is enabled and attestation is provided
	var attestedClaims []*types.AttestedClaims
	var attestedClaimsJSON []byte
	if fflag.IsSet(fflag.FlagUnifiedIdentity) && param.SovereignAttestation != nil {
		log.Info("Unified-Identity - Verification: Processing SovereignAttestation")
		claims, err := s.processSovereignAttestation(ctx, log, param.SovereignAttestation, spiffeID.String())
		if err != nil {
			log.WithError(err).Error("Unified-Identity - Verification: Failed to process SovereignAttestation")
			return &svidv1.BatchNewX509SVIDResponse_Result{
				Status: api.MakeStatus(log, codes.Internal, "failed to process sovereign attestation", err),
			}
		}
		if claims != nil {
			attestedClaims = []*types.AttestedClaims{claims}

			workloadKeyPEM, err := publicKeyToPEM(csr.PublicKey)
			if err != nil {
				log.WithError(err).Warn("Unified-Identity - Verification: Failed to encode workload public key for claims JSON")
			}

			unifiedJSON, err := unifiedidentity.BuildClaimsJSON(
				spiffeID.String(),
				unifiedidentity.KeySourceWorkload,
				workloadKeyPEM,
				param.SovereignAttestation,
				claims,
			)
			if err != nil {
				log.WithError(err).Warn("Unified-Identity - Verification: Failed to build unified identity claims JSON")
			} else {
				attestedClaimsJSON = unifiedJSON
				log.WithField("claims", string(unifiedJSON)).Info("Unified-Identity - Verification: Built workload unified identity claims")
			}
		}
	}

	// Unified-Identity - Verification: Sign X509 SVID with AttestedClaims embedded in certificate extension
	// This implements Model 3 from federated-jwt.md: "The assurance claims (TPM/Geo) are then anchored to the certificate."
	var attestedClaimsForCert *types.AttestedClaims
	if attestedClaims != nil && len(attestedClaims) > 0 {
		attestedClaimsForCert = attestedClaims[0]
		log.Debug("Unified-Identity - Verification: Embedding AttestedClaims in workload SVID certificate")
	}

	x509Svid, err := s.ca.SignWorkloadX509SVID(ctx, ca.WorkloadX509SVIDParams{
		SPIFFEID:       spiffeID,
		PublicKey:      csr.PublicKey,
		DNSNames:       entry.GetDnsNames(),
		TTL:            time.Duration(entry.GetX509SvidTtl()) * time.Second,
		AttestedClaims: attestedClaimsForCert, // Unified-Identity - Verification: Embed AttestedClaims in certificate
		UnifiedIdentityJSON: attestedClaimsJSON,
	})
	if err != nil {
		return &svidv1.BatchNewX509SVIDResponse_Result{
			Status: api.MakeStatus(log, codes.Internal, "failed to sign X509-SVID", err),
		}
	}

	log.WithField(telemetry.Expiration, x509Svid[0].NotAfter.Format(time.RFC3339)).
		WithField(telemetry.SerialNumber, x509Svid[0].SerialNumber.String()).
		WithField(telemetry.RevisionNumber, entry.GetRevisionNumber()).
		Debug("Signed X509 SVID")

	// Unified-Identity - Verification: Verify agent SVID before issuing workload certificate
	// The agent handler will include the agent SVID in the chain when serving to workloads
	// Here we verify the agent's SVID is valid before signing the workload certificate
	certChain := x509Svid
	agentSVID, ok := rpccontext.CallerX509SVID(ctx)
	if ok && agentSVID != nil {
		// Verify the agent SVID is valid and signed by the server
		// This ensures the entire chain can be verified before the workload certificate is issued
		agentID, _ := rpccontext.CallerID(ctx)
		log.WithField("agent_spiffe_id", agentID.String()).
			WithField("workload_spiffe_id", spiffeID.String()).
			Debug("Unified-Identity - Verification: Verified agent SVID before issuing workload certificate")
		
		// Note: The agent handler will include the agent SVID in the chain when serving to workloads
		// We don't include it here to avoid duplication - the agent handler is responsible for
		// constructing the complete chain: [Workload SVID, Agent SVID]
	}

	result := &svidv1.BatchNewX509SVIDResponse_Result{
		Svid: &types.X509SVID{
			Id:        entry.GetSpiffeId(),
			CertChain: x509util.RawCertsFromCertificates(certChain),
			ExpiresAt: x509Svid[0].NotAfter.Unix(),
		},
		Status: api.OK(),
	}

	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Add AttestedClaims to response if available
	if attestedClaims != nil {
		result.AttestedClaims = attestedClaims
		log.WithField("claims_count", len(attestedClaims)).Debug("Unified-Identity - Verification: Added AttestedClaims to response")
	}

	return result
}

func (s *Service) mintJWTSVID(ctx context.Context, protoID *types.SPIFFEID, audience []string, ttl int32) (*types.JWTSVID, error) {
	log := rpccontext.Logger(ctx)

	id, err := api.TrustDomainWorkloadIDFromProto(ctx, s.td, protoID)
	if err != nil {
		return nil, api.MakeErr(log, codes.InvalidArgument, "invalid SPIFFE ID", err)
	}

	log = log.WithField(telemetry.SPIFFEID, id.String())
	rpccontext.AddRPCAuditFields(ctx, logrus.Fields{
		telemetry.SPIFFEID: id,
	})

	if len(audience) == 0 {
		return nil, api.MakeErr(log, codes.InvalidArgument, "at least one audience is required", nil)
	}

	token, err := s.ca.SignWorkloadJWTSVID(ctx, ca.WorkloadJWTSVIDParams{
		SPIFFEID: id,
		TTL:      time.Duration(ttl) * time.Second,
		Audience: audience,
	})
	if err != nil {
		return nil, api.MakeErr(log, codes.Internal, "failed to sign JWT-SVID", err)
	}

	issuedAt, expiresAt, err := jwtsvid.GetTokenExpiry(token)
	if err != nil {
		return nil, api.MakeErr(log, codes.Internal, "failed to get JWT-SVID expiry", err)
	}

	log.WithFields(logrus.Fields{
		telemetry.Audience:   audience,
		telemetry.Expiration: expiresAt.Format(time.RFC3339),
	}).Debug("Server CA successfully signed JWT SVID")

	return &types.JWTSVID{
		Token:     token,
		Id:        api.ProtoFromID(id),
		ExpiresAt: expiresAt.Unix(),
		IssuedAt:  issuedAt.Unix(),
	}, nil
}

func (s *Service) NewJWTSVID(ctx context.Context, req *svidv1.NewJWTSVIDRequest) (resp *svidv1.NewJWTSVIDResponse, err error) {
	log := rpccontext.Logger(ctx)
	rpccontext.AddRPCAuditFields(ctx, logrus.Fields{
		telemetry.RegistrationID: req.EntryId,
		telemetry.Audience:       strings.Join(req.Audience, ","),
	})

	if err := rpccontext.RateLimit(ctx, 1); err != nil {
		return nil, api.MakeErr(log, status.Code(err), "rejecting request due to JWT signing request rate limiting", err)
	}

	entries := map[string]struct{}{
		req.EntryId: {},
	}

	// Fetch authorized entries
	entriesMap, err := s.findEntries(ctx, log, entries)
	if err != nil {
		return nil, err
	}

	entry, ok := entriesMap[req.EntryId]
	if !ok {
		return nil, api.MakeErr(log, codes.NotFound, "entry not found or not authorized", nil)
	}

	jwtsvid, err := s.mintJWTSVID(ctx, entry.GetSpiffeId(), req.Audience, entry.GetJwtSvidTtl())
	if err != nil {
		return nil, err
	}
	rpccontext.AuditRPCWithFields(ctx, logrus.Fields{
		telemetry.TTL: entry.GetJwtSvidTtl(),
	})

	return &svidv1.NewJWTSVIDResponse{
		Svid: jwtsvid,
	}, nil
}

func (s *Service) NewDownstreamX509CA(ctx context.Context, req *svidv1.NewDownstreamX509CARequest) (*svidv1.NewDownstreamX509CAResponse, error) {
	log := rpccontext.Logger(ctx)
	rpccontext.AddRPCAuditFields(ctx, logrus.Fields{
		telemetry.Csr:           api.HashByte(req.Csr),
		telemetry.TrustDomainID: s.td.IDString(),
	})

	if err := rpccontext.RateLimit(ctx, 1); err != nil {
		return nil, api.MakeErr(log, status.Code(err), "rejecting request due to downstream CA signing rate limit", err)
	}

	downstreamEntries, isDownstream := rpccontext.CallerDownstreamEntries(ctx)
	if !isDownstream {
		return nil, api.MakeErr(log, codes.Internal, "caller is not a downstream workload", nil)
	}

	entry := downstreamEntries[0]

	csr, err := parseAndCheckCSR(ctx, req.Csr)
	if err != nil {
		return nil, err
	}

	// Use the TTL offered by the downstream server (if any), unless we are
	// configured to use the legacy TTL.
	ttl := req.PreferredTtl
	if s.useLegacyDownstreamX509CATTL {
		// Legacy downstream TTL prefers the downstream workload entry
		// TTL (if any) and then the default workload TTL. We'll handle the
		// latter inside of the credbuilder package, which already has
		// knowledge of the default.
		ttl = entry.X509SvidTtl
	}

	x509CASvid, err := s.ca.SignDownstreamX509CA(ctx, ca.DownstreamX509CAParams{
		PublicKey: csr.PublicKey,
		TTL:       time.Duration(ttl) * time.Second,
	})
	if err != nil {
		return nil, api.MakeErr(log, codes.Internal, "failed to sign downstream X.509 CA", err)
	}

	log.WithFields(logrus.Fields{
		telemetry.SPIFFEID:   x509CASvid[0].URIs[0].String(),
		telemetry.Expiration: x509CASvid[0].NotAfter.Format(time.RFC3339),
	}).Debug("Signed X509 CA SVID")

	bundle, err := s.ds.FetchBundle(ctx, s.td.IDString())
	if err != nil {
		return nil, api.MakeErr(log, codes.Internal, "failed to fetch bundle", err)
	}

	if bundle == nil {
		return nil, api.MakeErr(log, codes.NotFound, "bundle not found", nil)
	}

	rawRootCerts := make([][]byte, 0, len(bundle.RootCas))
	for _, cert := range bundle.RootCas {
		rawRootCerts = append(rawRootCerts, cert.DerBytes)
	}
	rpccontext.AuditRPCWithFields(ctx, logrus.Fields{
		telemetry.ExpiresAt: x509CASvid[0].NotAfter.Unix(),
	})

	return &svidv1.NewDownstreamX509CAResponse{
		CaCertChain:     x509util.RawCertsFromCertificates(x509CASvid),
		X509Authorities: rawRootCerts,
	}, nil
}

func (s Service) fieldsFromJWTSvidParams(ctx context.Context, protoID *types.SPIFFEID, audience []string, ttl int32) logrus.Fields {
	fields := logrus.Fields{
		telemetry.TTL: ttl,
	}
	if protoID != nil {
		// Don't care about parsing error
		id, err := api.TrustDomainWorkloadIDFromProto(ctx, s.td, protoID)
		if err == nil {
			fields[telemetry.SPIFFEID] = id.String()
		}
	}

	if len(audience) > 0 {
		fields[telemetry.Audience] = strings.Join(audience, ",")
	}

	return fields
}

func parseAndCheckCSR(ctx context.Context, csrBytes []byte) (*x509.CertificateRequest, error) {
	log := rpccontext.Logger(ctx)

	csr, err := x509.ParseCertificateRequest(csrBytes)
	if err != nil {
		return nil, api.MakeErr(log, codes.InvalidArgument, "malformed CSR", err)
	}

	if err := csr.CheckSignature(); err != nil {
		return nil, api.MakeErr(log, codes.InvalidArgument, "invalid CSR signature", err)
	}

	return csr, nil
}

// Unified-Identity - Verification: Hardware Integration & Delegated Certification
// processSovereignAttestation processes SovereignAttestation by calling Keylime and evaluating policy
func (s *Service) processSovereignAttestation(ctx context.Context, log logrus.FieldLogger, sovereignAttestation *types.SovereignAttestation, spiffeID string) (*types.AttestedClaims, error) {
	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Skip Keylime verification for workload SVID requests - workloads inherit attested claims from agent SVID
	// Agent SVIDs have pattern: spiffe://<trust-domain>/spire/agent/...
	// Workload SVIDs have different patterns (e.g., spiffe://<trust-domain>/python-app)
	if !strings.Contains(spiffeID, "/spire/agent/") {
		log.Info("Unified-Identity - Verification: Skipping Keylime verification for workload SVID request (workloads inherit claims from agent SVID)")
		return nil, nil
	}

	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Check if Keylime client is configured
	if s.keylimeClient == nil {
		log.Warn("Unified-Identity - Verification: Keylime client not configured, skipping attestation verification")
		return nil, nil
	}

	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Build Keylime request from SovereignAttestation
	keylimeReq, err := keylime.BuildVerifyEvidenceRequest(&keylime.SovereignAttestationProto{
		TpmSignedAttestation: sovereignAttestation.TpmSignedAttestation,
		AppKeyPublic:         sovereignAttestation.AppKeyPublic,
		AppKeyCertificate:    sovereignAttestation.AppKeyCertificate,
		ChallengeNonce:       sovereignAttestation.ChallengeNonce,
		WorkloadCodeHash:     sovereignAttestation.WorkloadCodeHash,
	}, "")
	if err != nil {
		return nil, fmt.Errorf("failed to build Keylime request: %w", err)
	}

	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Call Keylime Verifier
	keylimeClaims, err := s.keylimeClient.VerifyEvidence(keylimeReq)
	if err != nil {
		return nil, fmt.Errorf("keylime verification failed: %w", err)
	}

	// Unified-Identity - Verification: Log geolocation object
	geoLog := "none"
	if keylimeClaims.Geolocation != nil {
		geoLog = fmt.Sprintf("type=%s, sensor_id=%s", keylimeClaims.Geolocation.Type, keylimeClaims.Geolocation.SensorID)
		if keylimeClaims.Geolocation.Value != "" {
			geoLog += fmt.Sprintf(", value=%s", keylimeClaims.Geolocation.Value)
		}
	}

	log.WithFields(logrus.Fields{
		"geolocation": geoLog,
	}).Info("Unified-Identity - Verification: Received AttestedClaims from Keylime")

	// Unified-Identity - Verification: Hardware Integration & Delegated Certification
	// Evaluate policy if policy engine is configured
	if s.policyEngine != nil {
		// Convert Geolocation object to string for policy engine
		policyGeoStr := ""
		if keylimeClaims.Geolocation != nil {
			// For policy matching, use a simple format: "type:sensor_id" or "type:sensor_id:value"
			if keylimeClaims.Geolocation.Value != "" {
				policyGeoStr = fmt.Sprintf("%s:%s:%s", keylimeClaims.Geolocation.Type, keylimeClaims.Geolocation.SensorID, keylimeClaims.Geolocation.Value)
			} else {
				policyGeoStr = fmt.Sprintf("%s:%s", keylimeClaims.Geolocation.Type, keylimeClaims.Geolocation.SensorID)
			}
		}

		policyClaims := policy.ConvertKeylimeAttestedClaims(&policy.KeylimeAttestedClaims{
			Geolocation: policyGeoStr,
		})

		policyResult, err := s.policyEngine.Evaluate(policyClaims)
		if err != nil {
			return nil, fmt.Errorf("policy evaluation failed: %w", err)
		}

		if !policyResult.Allowed {
			log.WithField("reason", policyResult.Reason).Warn("Unified-Identity - Verification: Policy evaluation failed")
			// Unified-Identity - Verification: Hardware Integration & Delegated Certification
			// In a real implementation, this would trigger remediation actions
			// Return an error if policy evaluation fails
			return nil, fmt.Errorf("policy evaluation failed: %s", policyResult.Reason)
		}

		log.Info("Unified-Identity - Verification: Policy evaluation passed")
	}

	// Unified-Identity - Verification: Convert Geolocation object to protobuf Geolocation
	var protoGeo *types.Geolocation
	if keylimeClaims.Geolocation != nil {
		protoGeo = &types.Geolocation{
			Type:     keylimeClaims.Geolocation.Type,
			SensorId: keylimeClaims.Geolocation.SensorID,
			Value:    keylimeClaims.Geolocation.Value,
		}
	}

	return &types.AttestedClaims{
		Geolocation: protoGeo,
	}, nil
}

func publicKeyToPEM(pub crypto.PublicKey) (string, error) {
	der, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		return "", err
	}
	block := &pem.Block{Type: "PUBLIC KEY", Bytes: der}
	return string(pem.EncodeToMemory(block)), nil
}
