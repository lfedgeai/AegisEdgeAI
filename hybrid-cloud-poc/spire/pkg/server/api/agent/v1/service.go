package agent

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
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
}

// Service implements the v1 agent service
type Service struct {
	agentv1.UnsafeAgentServer

	cat catalog.Catalog
	clk clock.Clock
	ds  datastore.DataStore
	ca  ca.ServerCA
	td  spiffeid.TrustDomain
}

// New creates a new agent service
func New(config Config) *Service {
	return &Service{
		cat: config.Catalog,
		clk: config.Clock,
		ds:  config.DataStore,
		ca:  config.ServerCA,
		td:  config.TrustDomain,
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

	// Unified-Identity: TPM-based proof of residency - derive agent ID from TPM evidence
	// If Unified-Identity is enabled and SovereignAttestation is present, use TPM-based attestation
	// instead of join_token or other node attestors
	var attestResult *nodeattestor.AttestResult
	if fflag.IsSet(fflag.FlagUnifiedIdentity) && params.Params != nil && params.Params.SovereignAttestation != nil {
		// Unified-Identity: Derive agent ID from TPM evidence (AK/EK via keylime_agent_uuid or App Key)
		agentIDStr, err := s.deriveAgentIDFromTPM(ctx, log, params.Params.SovereignAttestation)
		if err != nil {
			return api.MakeErr(log, codes.Internal, "failed to derive agent ID from TPM evidence", err)
		}
		attestResult = &nodeattestor.AttestResult{
			AgentID:     agentIDStr,
			CanReattest: true, // TPM-based attestation is re-attestable
		}
		log.WithField("agent_id", agentIDStr).Info("Unified-Identity: Derived agent ID from TPM evidence")
	} else if params.Data.Type == "join_token" {
		// Unified-Identity: If Unified-Identity is enabled and SovereignAttestation is present,
		// ignore join_token and use TPM-based attestation instead
		if fflag.IsSet(fflag.FlagUnifiedIdentity) && params.Params != nil && params.Params.SovereignAttestation != nil {
			// Derive agent ID from TPM evidence instead of join_token
			agentIDStr, err := s.deriveAgentIDFromTPM(ctx, log, params.Params.SovereignAttestation)
			if err != nil {
				return api.MakeErr(log, codes.Internal, "failed to derive agent ID from TPM evidence", err)
			}
			attestResult = &nodeattestor.AttestResult{
				AgentID:     agentIDStr,
				CanReattest: true,
			}
			log.WithField("agent_id", agentIDStr).Info("Unified-Identity: Ignored join_token, derived agent ID from TPM evidence")
		} else {
			attestResult, err = s.attestJoinToken(ctx, string(params.Data.Payload))
			if err != nil {
				return err
			}
		}
	} else if params.Data.Type == "unified_identity" {
		// Unified-Identity node attestor type - derive agent ID from TPM evidence
		// This handles the case where agent explicitly uses unified_identity node attestor
		if params.Params != nil && params.Params.SovereignAttestation != nil {
			agentIDStr, err := s.deriveAgentIDFromTPM(ctx, log, params.Params.SovereignAttestation)
			if err != nil {
				return api.MakeErr(log, codes.Internal, "failed to derive agent ID from TPM evidence", err)
			}
			attestResult = &nodeattestor.AttestResult{
				AgentID:     agentIDStr,
				CanReattest: true,
			}
			log.WithField("agent_id", agentIDStr).Info("Unified-Identity: Derived agent ID from TPM evidence (unified_identity type)")
		} else {
			return api.MakeErr(log, codes.InvalidArgument, "unified_identity node attestor requires SovereignAttestation", nil)
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

	// Unified-Identity - Verification: Pass SovereignAttestation to CredentialComposer via context
	if fflag.IsSet(fflag.FlagUnifiedIdentity) && params.Params != nil && params.Params.SovereignAttestation != nil {
		log.Debug("Unified-Identity - Verification: Passing SovereignAttestation to CredentialComposer via context")
		ctx = unifiedidentity.WithSovereignAttestation(ctx, params.Params.SovereignAttestation)
	}

	// parse and sign CSR
	svid, err := s.signSvid(ctx, agentID, params.Params.Csr, log)
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
	// Note: attestedClaims is no longer returned in the response as it is embedded in the SVID
	response := getAttestAgentResponse(agentID, svid, attestResult.CanReattest, nil)

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

	// Unified-Identity - Verification: Generate and return nonce if Unified Identity is enabled and no SovereignAttestation provided
	// Step 2: SPIRE Server generates nonce for TPM Quote freshness (per architecture doc)
	var challengeNonce []byte
	if fflag.IsSet(fflag.FlagUnifiedIdentity) && req.Params.SovereignAttestation == nil {
		// Generate cryptographically secure random nonce (32 bytes)
		nonceBytes := make([]byte, 32)
		if _, err := rand.Read(nonceBytes); err != nil {
			log.WithError(err).Warn("Unified-Identity - Verification: Failed to generate nonce")
		} else {
			challengeNonce = nonceBytes
			log.WithField("nonce_length", len(challengeNonce)).Info("Unified-Identity - Verification: Generated nonce for agent TPM Quote")
		}
	}

	// Unified-Identity - Verification: Pass SovereignAttestation to CredentialComposer via context
	if fflag.IsSet(fflag.FlagUnifiedIdentity) && req.Params.SovereignAttestation != nil {
		log.Debug("Unified-Identity - Verification: Passing SovereignAttestation (renewal) to CredentialComposer via context")
		ctx = unifiedidentity.WithSovereignAttestation(ctx, req.Params.SovereignAttestation)
	}

	agentSVID, err := s.signSvid(ctx, callerID, req.Params.Csr, log)
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

	resp := &agentv1.RenewAgentResponse{
		Svid: &types.X509SVID{
			Id:        api.ProtoFromID(callerID),
			ExpiresAt: agentSVID[0].NotAfter.Unix(),
			CertChain: x509util.RawCertsFromCertificates(agentSVID),
		},
		AttestedClaims: nil,
	}

	// Unified-Identity - Verification: Include challenge nonce in response if generated
	// This allows the agent to use the server-provided nonce for TPM Quote generation
	if len(challengeNonce) > 0 {
		resp.ChallengeNonce = challengeNonce
		log.WithField("nonce_length", len(challengeNonce)).Info("Unified-Identity - Verification: Returning nonce to agent for TPM Quote")
	}

	return resp, nil
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

func (s *Service) signSvid(ctx context.Context, agentID spiffeid.ID, csr []byte, log logrus.FieldLogger) ([]*x509.Certificate, error) {
	parsedCsr, err := x509.ParseCertificateRequest(csr)
	if err != nil {
		return nil, api.MakeErr(log, codes.InvalidArgument, "failed to parse CSR", err)
	}

	x509Svid, err := s.ca.SignAgentX509SVID(ctx, ca.AgentX509SVIDParams{
		SPIFFEID:  agentID,
		PublicKey: parsedCsr.PublicKey,
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

// Unified-Identity: Derive agent ID from TPM evidence (AK/EK)
// Uses keylime_agent_uuid if available, otherwise derives from App Key public key
func (s *Service) deriveAgentIDFromTPM(ctx context.Context, log logrus.FieldLogger, sovereignAttestation *types.SovereignAttestation) (string, error) {
	// Prefer keylime_agent_uuid if available (stable identifier from Keylime registrar)
	if sovereignAttestation.KeylimeAgentUuid != "" {
		agentPath := fmt.Sprintf("/unified_identity/%s", sovereignAttestation.KeylimeAgentUuid)
		agentID, err := idutil.AgentID(s.td, agentPath)
		if err != nil {
			return "", fmt.Errorf("failed to create agent ID from keylime_agent_uuid: %w", err)
		}
		return agentID.String(), nil
	}

	// Fallback: Derive from App Key public key (TPM-bound)
	if sovereignAttestation.AppKeyPublic != "" {
		// Hash the App Key public key to create a stable identifier
		hash := sha256.Sum256([]byte(sovereignAttestation.AppKeyPublic))
		fingerprint := hex.EncodeToString(hash[:])[:16] // Use first 16 chars for readability
		agentPath := fmt.Sprintf("/unified_identity/appkey-%s", fingerprint)
		agentID, err := idutil.AgentID(s.td, agentPath)
		if err != nil {
			return "", fmt.Errorf("failed to create agent ID from App Key: %w", err)
		}
		log.WithField("fingerprint", fingerprint).Debug("Unified-Identity: Derived agent ID from App Key public key")
		return agentID.String(), nil
	}

	return "", errors.New("unable to derive agent ID: missing keylime_agent_uuid and App Key public key")
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
