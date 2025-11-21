package agent

import (
	"context"
	"crypto/rand"
	"crypto/x509"
	"errors"
	"fmt"
	"time"

	"github.com/andres-erbsen/clock"
	"github.com/gofrs/uuid/v5"
	"github.com/sirupsen/logrus"
	"github.com/spiffe/go-spiffe/v2/spiffeid"
	agentv1 "github.com/spiffe/spire-api-sdk/proto/spire/api/server/agent/v1"
	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
	"github.com/spiffe/spire/pkg/common/errorutil"
	"github.com/spiffe/spire/pkg/common/fflag"
	"github.com/spiffe/spire/pkg/common/idutil"
	"github.com/spiffe/spire/pkg/common/nodeutil"
	"github.com/spiffe/spire/pkg/common/selector"
	"github.com/spiffe/spire/pkg/common/telemetry"
	"github.com/spiffe/spire/pkg/common/x509util"
	"github.com/spiffe/spire/pkg/server/api"
	"github.com/spiffe/spire/pkg/server/api/rpccontext"
	"github.com/spiffe/spire/pkg/server/ca"
	"github.com/spiffe/spire/pkg/server/catalog"
	"github.com/spiffe/spire/pkg/server/datastore"
	"github.com/spiffe/spire/pkg/server/plugin/nodeattestor"
	"github.com/spiffe/spire/pkg/server/policy"
	"github.com/spiffe/spire/pkg/server/keylime"
	"github.com/spiffe/spire/pkg/server/unifiedidentity"
	"github.com/spiffe/spire/proto/spire/common"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/peer"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/emptypb"
)

// Config is the service configuration
type Config struct {
	Catalog     catalog.Catalog
	Clock       clock.Clock
	DataStore   datastore.DataStore
	ServerCA    ca.ServerCA
	TrustDomain spiffeid.TrustDomain

	// Unified-Identity - Phase 3: Keylime client and policy engine
	KeylimeClient *keylime.Client
	PolicyEngine  *policy.Engine
}

// Service implements the v1 agent service
type Service struct {
	agentv1.UnsafeAgentServer

	cat catalog.Catalog
	clk clock.Clock
	ds  datastore.DataStore
	ca  ca.ServerCA
	td  spiffeid.TrustDomain

	// Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
	keylimeClient *keylime.Client
	policyEngine  *policy.Engine
}

// New creates a new agent service
func New(config Config) *Service {
	return &Service{
		cat: config.Catalog,
		clk: config.Clock,
		ds:  config.DataStore,
		ca:  config.ServerCA,
		td:  config.TrustDomain,
		keylimeClient: config.KeylimeClient,
		policyEngine:  config.PolicyEngine,
	}
}

// RegisterService registers the agent service on the gRPC server/
func RegisterService(s grpc.ServiceRegistrar, service *Service) {
	agentv1.RegisterAgentServer(s, service)
}

// CountAgents returns the total number of agents.
func (s *Service) CountAgents(ctx context.Context, req *agentv1.CountAgentsRequest) (*agentv1.CountAgentsResponse, error) {
	log := rpccontext.Logger(ctx)

	countReq := &datastore.CountAttestedNodesRequest{}

	// Parse proto filter into datastore request
	if req.Filter != nil {
		filter := req.Filter
		rpccontext.AddRPCAuditFields(ctx, fieldsFromCountAgentsRequest(filter))

		if filter.ByBanned != nil {
			countReq.ByBanned = &req.Filter.ByBanned.Value
		}
		if filter.ByCanReattest != nil {
			countReq.ByCanReattest = &req.Filter.ByCanReattest.Value
		}

		if filter.ByAttestationType != "" {
			countReq.ByAttestationType = filter.ByAttestationType
		}

		if filter.ByExpiresBefore != "" {
			countReq.ByExpiresBefore, _ = time.Parse("2006-01-02 15:04:05 -0700 -07", filter.ByExpiresBefore)
		}

		if filter.BySelectorMatch != nil {
			selectors, err := api.SelectorsFromProto(filter.BySelectorMatch.Selectors)
			if err != nil {
				return nil, api.MakeErr(log, codes.InvalidArgument, "failed to parse selectors", err)
			}
			countReq.BySelectorMatch = &datastore.BySelectors{
				Match:     datastore.MatchBehavior(filter.BySelectorMatch.Match),
				Selectors: selectors,
			}
		}
	}

	count, err := s.ds.CountAttestedNodes(ctx, countReq)
	if err != nil {
		log := rpccontext.Logger(ctx)
		return nil, api.MakeErr(log, codes.Internal, "failed to count agents", err)
	}
	rpccontext.AuditRPC(ctx)

	return &agentv1.CountAgentsResponse{Count: count}, nil
}

// ListAgents returns an optionally filtered and/or paginated list of agents.
func (s *Service) ListAgents(ctx context.Context, req *agentv1.ListAgentsRequest) (*agentv1.ListAgentsResponse, error) {
	log := rpccontext.Logger(ctx)

	listReq := &datastore.ListAttestedNodesRequest{}

	if req.OutputMask == nil || req.OutputMask.Selectors {
		listReq.FetchSelectors = true
	}
	// Parse proto filter into datastore request
	if req.Filter != nil {
		filter := req.Filter
		rpccontext.AddRPCAuditFields(ctx, fieldsFromListAgentsRequest(filter))

		if filter.ByBanned != nil {
			listReq.ByBanned = &req.Filter.ByBanned.Value
		}
		if filter.ByCanReattest != nil {
			listReq.ByCanReattest = &req.Filter.ByCanReattest.Value
		}

		if filter.ByAttestationType != "" {
			listReq.ByAttestationType = filter.ByAttestationType
		}

		if filter.ByExpiresBefore != "" {
			listReq.ByExpiresBefore, _ = time.Parse("2006-01-02 15:04:05 -0700 -07", filter.ByExpiresBefore)
		}

		if filter.BySelectorMatch != nil {
			selectors, err := api.SelectorsFromProto(filter.BySelectorMatch.Selectors)
			if err != nil {
				return nil, api.MakeErr(log, codes.InvalidArgument, "failed to parse selectors", err)
			}
			listReq.BySelectorMatch = &datastore.BySelectors{
				Match:     datastore.MatchBehavior(filter.BySelectorMatch.Match),
				Selectors: selectors,
			}
		}
	}

	// Set pagination parameters
	if req.PageSize > 0 {
		listReq.Pagination = &datastore.Pagination{
			PageSize: req.PageSize,
			Token:    req.PageToken,
		}
	}

	dsResp, err := s.ds.ListAttestedNodes(ctx, listReq)
	if err != nil {
		return nil, api.MakeErr(log, codes.Internal, "failed to list agents", err)
	}

	resp := &agentv1.ListAgentsResponse{}

	if dsResp.Pagination != nil {
		resp.NextPageToken = dsResp.Pagination.Token
	}

	// Parse nodes into proto and apply output mask
	for _, node := range dsResp.Nodes {
		a, err := api.ProtoFromAttestedNode(node)
		if err != nil {
			log.WithError(err).WithField(telemetry.SPIFFEID, node.SpiffeId).Warn("Failed to parse agent")
			continue
		}

		applyMask(a, req.OutputMask)
		resp.Agents = append(resp.Agents, a)
	}
	rpccontext.AuditRPC(ctx)

	return resp, nil
}

// GetAgent returns the agent associated with the given SpiffeID.
func (s *Service) GetAgent(ctx context.Context, req *agentv1.GetAgentRequest) (*types.Agent, error) {
	log := rpccontext.Logger(ctx)

	agentID, err := api.TrustDomainAgentIDFromProto(ctx, s.td, req.Id)
	if err != nil {
		return nil, api.MakeErr(log, codes.InvalidArgument, "invalid agent ID", err)
	}
	rpccontext.AddRPCAuditFields(ctx, logrus.Fields{telemetry.SPIFFEID: agentID.String()})

	log = log.WithField(telemetry.SPIFFEID, agentID.String())
	attestedNode, err := s.ds.FetchAttestedNode(ctx, agentID.String())
	if err != nil {
		return nil, api.MakeErr(log, codes.Internal, "failed to fetch agent", err)
	}

	if attestedNode == nil {
		return nil, api.MakeErr(log, codes.NotFound, "agent not found", err)
	}

	selectors, err := s.getSelectorsFromAgentID(ctx, attestedNode.SpiffeId)
	if err != nil {
		return nil, api.MakeErr(log, codes.Internal, "failed to get selectors from agent", err)
	}

	agent, err := api.AttestedNodeToProto(attestedNode, selectors)
	if err != nil {
		return nil, api.MakeErr(log, codes.Internal, "failed to convert attested node to agent", err)
	}

	rpccontext.AuditRPC(ctx)
	applyMask(agent, req.OutputMask)
	return agent, nil
}

// DeleteAgent removes the agent with the given SpiffeID.
func (s *Service) DeleteAgent(ctx context.Context, req *agentv1.DeleteAgentRequest) (*emptypb.Empty, error) {
	log := rpccontext.Logger(ctx)

	id, err := api.TrustDomainAgentIDFromProto(ctx, s.td, req.Id)
	if err != nil {
		return nil, api.MakeErr(log, codes.InvalidArgument, "invalid agent ID", err)
	}
	rpccontext.AddRPCAuditFields(ctx, logrus.Fields{telemetry.SPIFFEID: id.String()})

	log = log.WithField(telemetry.SPIFFEID, id.String())

	_, err = s.ds.DeleteAttestedNode(ctx, id.String())
	switch status.Code(err) {
	case codes.OK:
		log.Info("Agent deleted")
		rpccontext.AuditRPC(ctx)
		return &emptypb.Empty{}, nil
	case codes.NotFound:
		return nil, api.MakeErr(log, codes.NotFound, "agent not found", err)
	default:
		return nil, api.MakeErr(log, codes.Internal, "failed to remove agent", err)
	}
}

// BanAgent sets the agent with the given SpiffeID to the banned state.
func (s *Service) BanAgent(ctx context.Context, req *agentv1.BanAgentRequest) (*emptypb.Empty, error) {
	log := rpccontext.Logger(ctx)

	id, err := api.TrustDomainAgentIDFromProto(ctx, s.td, req.Id)
	if err != nil {
		return nil, api.MakeErr(log, codes.InvalidArgument, "invalid agent ID", err)
	}
	rpccontext.AddRPCAuditFields(ctx, logrus.Fields{telemetry.SPIFFEID: id.String()})

	log = log.WithField(telemetry.SPIFFEID, id.String())

	// The agent "Banned" state is pointed out by setting its
	// serial numbers (current and new) to empty strings.
	banned := &common.AttestedNode{SpiffeId: id.String()}
	mask := &common.AttestedNodeMask{
		CertSerialNumber:    true,
		NewCertSerialNumber: true,
	}
	_, err = s.ds.UpdateAttestedNode(ctx, banned, mask)

	switch status.Code(err) {
	case codes.OK:
		log.Info("Agent banned")
		rpccontext.AuditRPC(ctx)
		return &emptypb.Empty{}, nil
	case codes.NotFound:
		return nil, api.MakeErr(log, codes.NotFound, "agent not found", err)
	default:
		return nil, api.MakeErr(log, codes.Internal, "failed to ban agent", err)
	}
}

// AttestAgent attests the authenticity of the given agent.
func (s *Service) AttestAgent(stream agentv1.Agent_AttestAgentServer) error {
	ctx := stream.Context()
	log := rpccontext.Logger(ctx)

	if err := rpccontext.RateLimit(ctx, 1); err != nil {
		return api.MakeErr(log, status.Code(err), "rejecting request due to attest agent rate limiting", err)
	}

	req, err := stream.Recv()
	if err != nil {
		return api.MakeErr(log, codes.InvalidArgument, "failed to receive request from stream", err)
	}

	// validate
	params := req.GetParams()
	if err := validateAttestAgentParams(params); err != nil {
		return api.MakeErr(log, codes.InvalidArgument, "malformed param", err)
	}
	rpccontext.AddRPCAuditFields(ctx, logrus.Fields{
		telemetry.NodeAttestorType: params.Data.Type,
	})

	log = log.WithField(telemetry.NodeAttestorType, params.Data.Type)

	// attest
	var attestResult *nodeattestor.AttestResult
	if params.Data.Type == "join_token" {
		attestResult, err = s.attestJoinToken(ctx, string(params.Data.Payload))
		if err != nil {
			return err
		}
	} else {
		attestResult, err = s.attestChallengeResponse(ctx, stream, params)
		if err != nil {
			return err
		}
	}

	agentID, err := spiffeid.FromString(attestResult.AgentID)
	if err != nil {
		return api.MakeErr(log, codes.Internal, "invalid agent ID", err)
	}

	log = log.WithField(telemetry.AgentID, agentID)
	rpccontext.AddRPCAuditFields(ctx, logrus.Fields{telemetry.AgentID: agentID})

	// Ideally we'd do stronger validation that the ID is within the Node
	// Attestors scoped area of the reserved agent namespace, but historically
	// we haven't been strict here and there are deployments that are emitting
	// such IDs.
	// Deprecated: enforce that IDs produced by Node Attestors are in the
	// reserved namespace for that Node Attestor starting in SPIRE 1.4.
	if agentID.Path() == idutil.ServerIDPath {
		return api.MakeErr(log, codes.Internal, "agent ID cannot collide with the server ID", nil)
	}
	if err := api.VerifyTrustDomainAgentIDForNodeAttestor(s.td, agentID, params.Data.Type); err != nil {
		log.WithError(err).Warn("The node attestor produced an invalid agent ID; future releases will enforce that agent IDs are within the reserved agent namesepace for the node attestor")
	}

	// fetch the agent/node to check if it was already attested or banned
	attestedNode, err := s.ds.FetchAttestedNode(ctx, agentID.String())
	if err != nil {
		return api.MakeErr(log, codes.Internal, "failed to fetch agent", err)
	}

	if attestedNode != nil && nodeutil.IsAgentBanned(attestedNode) {
		return api.MakeErr(log, codes.PermissionDenied, "failed to attest: agent is banned", nil)
	}

	// Unified-Identity - Phase 3: Process AttestedClaims BEFORE signing SVID
	// This allows AttestedClaims to be embedded in the certificate extension (Model 3 from federated-jwt.md)
	var attestedClaims []*types.AttestedClaims
	var attestedClaimsForCert *types.AttestedClaims
	var attestedClaimsJSON []byte
	if fflag.IsSet(fflag.FlagUnifiedIdentity) {
		if params.Params != nil {
			if params.Params.SovereignAttestation != nil {
				log.Debug("Unified-Identity - Phase 3: Received SovereignAttestation in agent bootstrap request")
				claims, err := s.processSovereignAttestation(ctx, log, params.Params.SovereignAttestation, agentID.String())
				if err != nil {
					return api.MakeErr(log, codes.Internal, "failed to process sovereign attestation", err)
				}
				if claims != nil {
					attestedClaims = []*types.AttestedClaims{claims}
					attestedClaimsForCert = claims
					unifiedJSON, err := unifiedidentity.BuildClaimsJSON(
						agentID.String(),
						unifiedidentity.KeySourceTPMApp,
						"",
						params.Params.SovereignAttestation,
						claims,
					)
					if err != nil {
						log.WithError(err).Warn("Unified-Identity - Phase 3: Failed to build unified identity claims JSON for agent SVID")
					} else {
						attestedClaimsJSON = unifiedJSON
						log.WithField("claims", string(unifiedJSON)).Info("Unified-Identity - Phase 3: Built agent unified identity claims")
					}
					log.WithFields(logrus.Fields{
						"geolocation": claims.Geolocation,
					}).Info("Unified-Identity - Phase 3: AttestedClaims will be embedded in agent SVID certificate")
				} else {
					log.Warn("Unified-Identity - Phase 3: processSovereignAttestation returned nil claims")
				}
			} else {
				log.Warn("Unified-Identity - Phase 3: SovereignAttestation is nil in agent attestation params")
			}
		} else {
			log.Warn("Unified-Identity - Phase 3: params.Params is nil in agent attestation request")
		}
	}

	// parse and sign CSR with AttestedClaims embedded in certificate
	svid, err := s.signSvid(ctx, agentID, params.Params.Csr, log, attestedClaimsForCert, attestedClaimsJSON)
	if err != nil {
		return err
	}

	// dedupe and store node selectors
	err = s.ds.SetNodeSelectors(ctx, agentID.String(), selector.Dedupe(attestResult.Selectors))
	if err != nil {
		return api.MakeErr(log, codes.Internal, "failed to update selectors", err)
	}

	// create or update attested entry
	if attestedNode == nil {
		node := &common.AttestedNode{
			AttestationDataType: params.Data.Type,
			SpiffeId:            agentID.String(),
			CertNotAfter:        svid[0].NotAfter.Unix(),
			CertSerialNumber:    svid[0].SerialNumber.String(),
			CanReattest:         attestResult.CanReattest,
		}
		if _, err := s.ds.CreateAttestedNode(ctx, node); err != nil {
			return api.MakeErr(log, codes.Internal, "failed to create attested agent", err)
		}
	} else {
		node := &common.AttestedNode{
			SpiffeId:         agentID.String(),
			CertNotAfter:     svid[0].NotAfter.Unix(),
			CertSerialNumber: svid[0].SerialNumber.String(),
			CanReattest:      attestResult.CanReattest,
		}
		if _, err := s.ds.UpdateAttestedNode(ctx, node, nil); err != nil {
			return api.MakeErr(log, codes.Internal, "failed to update attested agent", err)
		}
	}

	// build and send response
	response := getAttestAgentResponse(agentID, svid, attestResult.CanReattest, attestedClaims)

	if p, ok := peer.FromContext(ctx); ok {
		log = log.WithField(telemetry.Address, p.Addr.String())
	}
	log.Info("Agent attestation request completed")

	if err := stream.Send(response); err != nil {
		return api.MakeErr(log, codes.Internal, "failed to send response over stream", err)
	}
	rpccontext.AuditRPC(ctx)

	return nil
}

// RenewAgent renews the SVID of the agent with the given SpiffeID.
func (s *Service) RenewAgent(ctx context.Context, req *agentv1.RenewAgentRequest) (*agentv1.RenewAgentResponse, error) {
	log := rpccontext.Logger(ctx)
	if req.Params != nil && len(req.Params.Csr) > 0 {
		rpccontext.AddRPCAuditFields(ctx, logrus.Fields{telemetry.Csr: api.HashByte(req.Params.Csr)})
	}

	if err := rpccontext.RateLimit(ctx, 1); err != nil {
		return nil, api.MakeErr(log, status.Code(err), "rejecting request due to renew agent rate limiting", err)
	}

	callerID, ok := rpccontext.CallerID(ctx)
	if !ok {
		return nil, api.MakeErr(log, codes.Internal, "caller ID missing from request context", nil)
	}

	attestedNode, err := s.ds.FetchAttestedNode(ctx, callerID.String())
	if err != nil {
		return nil, api.MakeErr(log, codes.Internal, "failed to fetch agent", err)
	}

	if attestedNode == nil {
		return nil, api.MakeErr(log, codes.NotFound, "agent not found", err)
	}

	// Agent attempted to renew when it should've been reattesting
	if attestedNode.CanReattest {
		return nil, errorutil.PermissionDenied(types.PermissionDeniedDetails_AGENT_MUST_REATTEST, "agent must reattest instead of renew")
	}

	log.Info("Renewing agent SVID")

	if req.Params == nil {
		return nil, api.MakeErr(log, codes.InvalidArgument, "params cannot be nil", nil)
	}
	if len(req.Params.Csr) == 0 {
		return nil, api.MakeErr(log, codes.InvalidArgument, "missing CSR", nil)
	}

	// Unified-Identity - Phase 3: Generate and return nonce if Unified Identity is enabled and no SovereignAttestation provided
	// Step 2: SPIRE Server generates nonce for TPM Quote freshness (per architecture doc)
	var challengeNonce []byte
	if fflag.IsSet(fflag.FlagUnifiedIdentity) && req.Params.SovereignAttestation == nil {
		// Generate cryptographically secure random nonce (32 bytes)
		nonceBytes := make([]byte, 32)
		if _, err := rand.Read(nonceBytes); err != nil {
			log.WithError(err).Warn("Unified-Identity - Phase 3: Failed to generate nonce")
		} else {
			challengeNonce = nonceBytes
			log.WithField("nonce_length", len(challengeNonce)).Info("Unified-Identity - Phase 3: Generated nonce for agent TPM Quote")
		}
	}

	// Unified-Identity - Phase 3: Process AttestedClaims BEFORE signing SVID
	// This allows AttestedClaims to be embedded in the certificate extension (Model 3 from federated-jwt.md)
	var attestedClaims []*types.AttestedClaims
	var attestedClaimsForCert *types.AttestedClaims
	var attestedClaimsJSON []byte
	if fflag.IsSet(fflag.FlagUnifiedIdentity) && req.Params.SovereignAttestation != nil {
		claims, err := s.processSovereignAttestation(ctx, log, req.Params.SovereignAttestation, callerID.String())
		if err != nil {
			return nil, api.MakeErr(log, codes.Internal, "failed to process sovereign attestation", err)
		}
		if claims != nil {
			attestedClaims = []*types.AttestedClaims{claims}
			attestedClaimsForCert = claims
			unifiedJSON, err := unifiedidentity.BuildClaimsJSON(
				callerID.String(),
				unifiedidentity.KeySourceTPMApp,
				"",
				req.Params.SovereignAttestation,
				claims,
			)
			if err != nil {
				log.WithError(err).Warn("Unified-Identity - Phase 3: Failed to build unified identity claims JSON for agent renew")
			} else {
				attestedClaimsJSON = unifiedJSON
				log.WithField("claims", string(unifiedJSON)).Info("Unified-Identity - Phase 3: Built agent unified identity claims (renew)")
			}
			log.WithFields(logrus.Fields{
				"geolocation": claims.Geolocation,
			}).Info("Unified-Identity - Phase 3: AttestedClaims will be embedded in agent SVID certificate")
		}
	}

	agentSVID, err := s.signSvid(ctx, callerID, req.Params.Csr, log, attestedClaimsForCert, attestedClaimsJSON)
	if err != nil {
		return nil, err
	}

	update := &common.AttestedNode{
		SpiffeId:            callerID.String(),
		NewCertNotAfter:     agentSVID[0].NotAfter.Unix(),
		NewCertSerialNumber: agentSVID[0].SerialNumber.String(),
	}
	mask := &common.AttestedNodeMask{
		NewCertNotAfter:     true,
		NewCertSerialNumber: true,
	}
	if err := s.updateAttestedNode(ctx, update, mask, log); err != nil {
		return nil, err
	}
	rpccontext.AuditRPC(ctx)

	// Send response with new X509 SVID
	if len(attestedClaims) > 0 {
		claim := attestedClaims[0]
		log.WithFields(logrus.Fields{
			"geolocation": claim.Geolocation,
		}).Info("Unified-Identity - Phase 3: AttestedClaims attached to agent SVID")
	}

	resp := &agentv1.RenewAgentResponse{
		Svid: &types.X509SVID{
			Id:        api.ProtoFromID(callerID),
			ExpiresAt: agentSVID[0].NotAfter.Unix(),
			CertChain: x509util.RawCertsFromCertificates(agentSVID),
		},
		AttestedClaims: attestedClaims,
	}

	// Unified-Identity - Phase 3: Include challenge nonce in response if generated
	// This allows the agent to use the server-provided nonce for TPM Quote generation
	if len(challengeNonce) > 0 {
		resp.ChallengeNonce = challengeNonce
		log.WithField("nonce_length", len(challengeNonce)).Info("Unified-Identity - Phase 3: Returning nonce to agent for TPM Quote")
	}

	return resp, nil
}

// Unified-Identity - Phase 3: Process SovereignAttestation for agent renewals
func (s *Service) processSovereignAttestation(ctx context.Context, log logrus.FieldLogger, sovereignAttestation *types.SovereignAttestation, spiffeID string) (*types.AttestedClaims, error) {
	if s.keylimeClient == nil {
		log.Warn("Unified-Identity - Phase 3: Keylime client not configured, skipping attestation verification")
		return nil, nil
	}

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

	keylimeClaims, err := s.keylimeClient.VerifyEvidence(keylimeReq)
	if err != nil {
		return nil, fmt.Errorf("keylime verification failed: %w", err)
	}

	// Unified-Identity - Phase 3: Log geolocation object
	geoLog := "none"
	if keylimeClaims.Geolocation != nil {
		geoLog = fmt.Sprintf("type=%s, sensor_id=%s", keylimeClaims.Geolocation.Type, keylimeClaims.Geolocation.SensorID)
		if keylimeClaims.Geolocation.Value != "" {
			geoLog += fmt.Sprintf(", value=%s", keylimeClaims.Geolocation.Value)
		}
	}

	log.WithFields(logrus.Fields{
		"geolocation": geoLog,
	}).Info("Unified-Identity - Phase 3: Received AttestedClaims from Keylime (agent)")

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
			log.WithField("reason", policyResult.Reason).Warn("Unified-Identity - Phase 3: Policy evaluation failed for agent")
			return nil, fmt.Errorf("policy evaluation failed: %s", policyResult.Reason)
		}

		log.Info("Unified-Identity - Phase 3: Policy evaluation passed for agent")
	}

	// Unified-Identity - Phase 3: Convert Geolocation object to protobuf Geolocation
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

// PostStatus post agent status
func (s *Service) PostStatus(context.Context, *agentv1.PostStatusRequest) (*agentv1.PostStatusResponse, error) {
	return nil, status.Error(codes.Unimplemented, "unimplemented")
}

// CreateJoinToken returns a new JoinToken for an agent.
func (s *Service) CreateJoinToken(ctx context.Context, req *agentv1.CreateJoinTokenRequest) (*types.JoinToken, error) {
	log := rpccontext.Logger(ctx)
	parseRequest := func() logrus.Fields {
		fields := logrus.Fields{}

		if req.Ttl > 0 {
			fields[telemetry.TTL] = req.Ttl
		}
		return fields
	}
	rpccontext.AddRPCAuditFields(ctx, parseRequest())

	if req.Ttl < 1 {
		return nil, api.MakeErr(log, codes.InvalidArgument, "ttl is required, you must provide one", nil)
	}

	// If provided, check that the AgentID is valid BEFORE creating the join token so we can fail early
	var agentID spiffeid.ID
	var err error
	if req.AgentId != nil {
		agentID, err = api.TrustDomainWorkloadIDFromProto(ctx, s.td, req.AgentId)
		if err != nil {
			return nil, api.MakeErr(log, codes.InvalidArgument, "invalid agent ID", err)
		}
		rpccontext.AddRPCAuditFields(ctx, logrus.Fields{telemetry.SPIFFEID: agentID.String()})
		log.WithField(telemetry.SPIFFEID, agentID.String())
	}

	// Generate a token if one wasn't specified
	if req.Token == "" {
		u, err := uuid.NewV4()
		if err != nil {
			return nil, api.MakeErr(log, codes.Internal, "failed to generate token UUID", err)
		}
		req.Token = u.String()
	}

	expiry := s.clk.Now().Add(time.Second * time.Duration(req.Ttl))

	err = s.ds.CreateJoinToken(ctx, &datastore.JoinToken{
		Token:  req.Token,
		Expiry: expiry,
	})
	if err != nil {
		return nil, api.MakeErr(log, codes.Internal, "failed to create token", err)
	}

	if req.AgentId != nil {
		err := s.createJoinTokenRegistrationEntry(ctx, req.Token, agentID.String())
		if err != nil {
			return nil, api.MakeErr(log, codes.Internal, "failed to create join token registration entry", err)
		}
	}
	rpccontext.AuditRPC(ctx)

	return &types.JoinToken{Value: req.Token, ExpiresAt: expiry.Unix()}, nil
}

func (s *Service) createJoinTokenRegistrationEntry(ctx context.Context, token string, agentID string) error {
	parentID, err := joinTokenID(s.td, token)
	if err != nil {
		return fmt.Errorf("failed to create join token ID: %w", err)
	}
	entry := &common.RegistrationEntry{
		ParentId: parentID.String(),
		SpiffeId: agentID,
		Selectors: []*common.Selector{
			{Type: "spiffe_id", Value: parentID.String()},
		},
	}
	_, err = s.ds.CreateRegistrationEntry(ctx, entry)
	return err
}

func (s *Service) updateAttestedNode(ctx context.Context, node *common.AttestedNode, mask *common.AttestedNodeMask, log logrus.FieldLogger) error {
	_, err := s.ds.UpdateAttestedNode(ctx, node, mask)
	switch status.Code(err) {
	case codes.OK:
		return nil
	case codes.NotFound:
		return api.MakeErr(log, codes.NotFound, "agent not found", err)
	default:
		return api.MakeErr(log, codes.Internal, "failed to update agent", err)
	}
}

func (s *Service) signSvid(ctx context.Context, agentID spiffeid.ID, csr []byte, log logrus.FieldLogger, attestedClaims *types.AttestedClaims, attestedClaimsJSON []byte) ([]*x509.Certificate, error) {
	parsedCsr, err := x509.ParseCertificateRequest(csr)
	if err != nil {
		return nil, api.MakeErr(log, codes.InvalidArgument, "failed to parse CSR", err)
	}

	// Unified-Identity - Phase 3: Sign X509 SVID with AttestedClaims embedded in certificate extension
	// This implements Model 3 from federated-jwt.md: "The assurance claims (TPM/Geo) are then anchored to the certificate."
	x509Svid, err := s.ca.SignAgentX509SVID(ctx, ca.AgentX509SVIDParams{
		SPIFFEID:       agentID,
		PublicKey:      parsedCsr.PublicKey,
		AttestedClaims: attestedClaims, // Unified-Identity - Phase 3: Embed AttestedClaims in certificate
		UnifiedIdentityJSON: attestedClaimsJSON,
	})
	if err != nil {
		return nil, api.MakeErr(log, codes.Internal, "failed to sign X509 SVID", err)
	}

	return x509Svid, nil
}

func (s *Service) getSelectorsFromAgentID(ctx context.Context, agentID string) ([]*types.Selector, error) {
	selectors, err := s.ds.GetNodeSelectors(ctx, agentID, datastore.RequireCurrent)
	if err != nil {
		return nil, fmt.Errorf("failed to get node selectors: %w", err)
	}

	return api.ProtoFromSelectors(selectors), nil
}

func (s *Service) attestJoinToken(ctx context.Context, token string) (*nodeattestor.AttestResult, error) {
	log := rpccontext.Logger(ctx).WithField(telemetry.NodeAttestorType, "join_token")

	joinToken, err := s.ds.FetchJoinToken(ctx, token)
	switch {
	case err != nil:
		return nil, api.MakeErr(log, codes.Internal, "failed to fetch join token", err)
	case joinToken == nil:
		return nil, api.MakeErr(log, codes.InvalidArgument, "failed to attest: join token does not exist or has already been used", nil)
	}

	err = s.ds.DeleteJoinToken(ctx, token)
	switch {
	case err != nil:
		return nil, api.MakeErr(log, codes.Internal, "failed to delete join token", err)
	case joinToken.Expiry.Before(s.clk.Now()):
		return nil, api.MakeErr(log, codes.InvalidArgument, "join token expired", nil)
	}

	agentID, err := joinTokenID(s.td, token)
	if err != nil {
		return nil, api.MakeErr(log, codes.Internal, "failed to create join token ID", err)
	}

	return &nodeattestor.AttestResult{
		AgentID: agentID.String(),
	}, nil
}

func (s *Service) attestChallengeResponse(ctx context.Context, agentStream agentv1.Agent_AttestAgentServer, params *agentv1.AttestAgentRequest_Params) (*nodeattestor.AttestResult, error) {
	attestorType := params.Data.Type
	log := rpccontext.Logger(ctx).WithField(telemetry.NodeAttestorType, attestorType)

	nodeAttestor, ok := s.cat.GetNodeAttestorNamed(attestorType)
	if !ok {
		return nil, api.MakeErr(log, codes.FailedPrecondition, "error getting node attestor", fmt.Errorf("could not find node attestor type %q", attestorType))
	}

	result, err := nodeAttestor.Attest(ctx, params.Data.Payload, func(ctx context.Context, challenge []byte) ([]byte, error) {
		resp := &agentv1.AttestAgentResponse{
			Step: &agentv1.AttestAgentResponse_Challenge{
				Challenge: challenge,
			},
		}
		if err := agentStream.Send(resp); err != nil {
			return nil, api.MakeErr(log, codes.Internal, "failed to send challenge to agent", err)
		}

		req, err := agentStream.Recv()
		if err != nil {
			return nil, api.MakeErr(log, codes.Internal, "failed to receive challenge from agent", err)
		}

		return req.GetChallengeResponse(), nil
	})
	if err != nil {
		st := status.Convert(err)
		return nil, api.MakeErr(log, st.Code(), st.Message(), nil)
	}
	return result, nil
}

func applyMask(a *types.Agent, mask *types.AgentMask) {
	if mask == nil {
		return
	}
	if !mask.AttestationType {
		a.AttestationType = ""
	}

	if !mask.X509SvidSerialNumber {
		a.X509SvidSerialNumber = ""
	}

	if !mask.X509SvidExpiresAt {
		a.X509SvidExpiresAt = 0
	}

	if !mask.Selectors {
		a.Selectors = nil
	}

	if !mask.Banned {
		a.Banned = false
	}

	if !mask.CanReattest {
		a.CanReattest = false
	}
}

func validateAttestAgentParams(params *agentv1.AttestAgentRequest_Params) error {
	switch {
	case params == nil:
		return errors.New("missing params")
	case params.Data == nil:
		return errors.New("missing attestation data")
	case params.Params == nil:
		return errors.New("missing X509-SVID parameters")
	case len(params.Params.Csr) == 0:
		return errors.New("missing CSR")
	case params.Data.Type == "":
		return errors.New("missing attestation data type")
	case len(params.Data.Payload) == 0:
		return errors.New("missing attestation data payload")
	default:
		return nil
	}
}

func getAttestAgentResponse(spiffeID spiffeid.ID, certificates []*x509.Certificate, canReattest bool, attestedClaims []*types.AttestedClaims) *agentv1.AttestAgentResponse {
	svid := &types.X509SVID{
		Id:        api.ProtoFromID(spiffeID),
		CertChain: x509util.RawCertsFromCertificates(certificates),
		ExpiresAt: certificates[0].NotAfter.Unix(),
	}

	return &agentv1.AttestAgentResponse{
		Step: &agentv1.AttestAgentResponse_Result_{
			Result: &agentv1.AttestAgentResponse_Result{
				Svid:           svid,
				Reattestable:   canReattest,
				AttestedClaims: attestedClaims,
			},
		},
	}
}

func fieldsFromListAgentsRequest(filter *agentv1.ListAgentsRequest_Filter) logrus.Fields {
	fields := logrus.Fields{}

	if filter.ByAttestationType != "" {
		fields[telemetry.NodeAttestorType] = filter.ByAttestationType
	}

	if filter.ByBanned != nil {
		fields[telemetry.ByBanned] = filter.ByBanned.Value
	}

	if filter.ByCanReattest != nil {
		fields[telemetry.ByCanReattest] = filter.ByCanReattest.Value
	}

	if filter.BySelectorMatch != nil {
		fields[telemetry.BySelectorMatch] = filter.BySelectorMatch.Match.String()
		fields[telemetry.BySelectors] = api.SelectorFieldFromProto(filter.BySelectorMatch.Selectors)
	}

	return fields
}

func fieldsFromCountAgentsRequest(filter *agentv1.CountAgentsRequest_Filter) logrus.Fields {
	fields := logrus.Fields{}

	if filter.ByAttestationType != "" {
		fields[telemetry.NodeAttestorType] = filter.ByAttestationType
	}

	if filter.ByBanned != nil {
		fields[telemetry.ByBanned] = filter.ByBanned.Value
	}

	if filter.ByCanReattest != nil {
		fields[telemetry.ByCanReattest] = filter.ByCanReattest.Value
	}

	if filter.BySelectorMatch != nil {
		fields[telemetry.BySelectorMatch] = filter.BySelectorMatch.Match.String()
		fields[telemetry.BySelectors] = api.SelectorFieldFromProto(filter.BySelectorMatch.Selectors)
	}

	return fields
}

func joinTokenID(td spiffeid.TrustDomain, token string) (spiffeid.ID, error) {
	return spiffeid.FromSegments(td, "spire", "agent", "join_token", token)
}
