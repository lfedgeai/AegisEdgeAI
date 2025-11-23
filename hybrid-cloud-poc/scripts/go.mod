module github.com/lfedgeai/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1/scripts

go 1.23.0

toolchain go1.24.10

require (
	github.com/spiffe/go-spiffe/v2 v2.5.0
	github.com/spiffe/spire-api-sdk v1.2.5-0.20250109200630-101d5e7de758
	google.golang.org/grpc v1.74.2
)

require (
	golang.org/x/net v0.43.0 // indirect
	golang.org/x/sys v0.35.0 // indirect
	golang.org/x/text v0.28.0 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20250811230008-5f3141c8851a // indirect
	google.golang.org/protobuf v1.36.7 // indirect
)

replace github.com/spiffe/spire-api-sdk => ../spire-api-sdk
