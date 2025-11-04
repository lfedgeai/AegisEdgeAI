//go:build unified_identity

package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/spiffe/go-spiffe/v2/workloadapi"
	"github.com/spiffe/go-spiffe/v2/proto/spiffe/workload"
)

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	client, err := workloadapi.New(ctx)
	if err != nil {
		log.Fatalf("Unable to create workload API client: %v", err)
	}
	defer client.Close()

	stream, err := client.PerformSovereignAttestation(ctx, &workload.PerformSovereignAttestationRequest{
		AttestationData: []byte("stubbed-attestation-data"),
	})
	if err != nil {
		log.Fatalf("Unable to perform sovereign attestation: %v", err)
	}

	resp, err := stream.Recv()
	if err != nil {
		log.Fatalf("Unable to receive sovereign attestation response: %v", err)
	}

	if string(resp.Challenge) != "stubbed-challenge" {
		log.Fatalf("Unexpected challenge: %s", resp.Challenge)
	}

	if resp.Metadata["provider"] != "stubbed-keylime" {
		log.Fatalf("Unexpected metadata: %v", resp.Metadata)
	}

	fmt.Println("Successfully performed sovereign attestation")
}
