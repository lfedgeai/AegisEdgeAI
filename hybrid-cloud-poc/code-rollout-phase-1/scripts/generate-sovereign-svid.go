// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// This script generates an X509-SVID with SovereignAttestation using the SPIRE API.
package main

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"net"
	"net/url"
	"strings"
	"time"

	"github.com/spiffe/go-spiffe/v2/spiffeid"
	svidv1 "github.com/spiffe/spire-api-sdk/proto/spire/api/server/svid/v1"
	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

var (
	serverSocketPath = flag.String("serverSocketPath", "unix:///tmp/spire-server/private/api.sock", "SPIRE Server socket path")
	entryID          = flag.String("entryID", "", "Registration entry ID (required)")
	spiffeID         = flag.String("spiffeID", "spiffe://example.org/workload/test", "SPIFFE ID for the workload")
	outputCert       = flag.String("outputCert", "svid.crt", "Output file for the SVID certificate")
	outputKey        = flag.String("outputKey", "svid.key", "Output file for the private key")
	verbose          = flag.Bool("verbose", false, "Enable verbose logging")
)

func main() {
	flag.Parse()

	if *entryID == "" {
		log.Fatal("Error: entryID is required. Use -entryID flag")
	}

	log.SetFlags(0)
	if *verbose {
		log.SetFlags(log.LstdFlags | log.Lshortfile)
	}

	log.Println("Unified-Identity - Phase 1: Generating SVID with SovereignAttestation")

	// Step 1: Generate CSR
	log.Println("Step 1: Generating CSR...")
	csr, privateKey, err := generateCSR(*spiffeID)
	if err != nil {
		log.Fatalf("Failed to generate CSR: %v", err)
	}
	log.Printf("✓ CSR generated for SPIFFE ID: %s", *spiffeID)

	// Step 2: Prepare SovereignAttestation (stubbed for Phase 1)
	log.Println("Step 2: Preparing SovereignAttestation (stubbed)...")
	sovereignAttestation := createStubbedSovereignAttestation()
	log.Println("✓ SovereignAttestation prepared")

	// Step 3: Connect to SPIRE Server
	log.Printf("Step 3: Connecting to SPIRE Server at %s...", *serverSocketPath)
	
	// Parse socket path (remove unix:// prefix if present)
	socketPath := strings.TrimPrefix(*serverSocketPath, "unix://")
	
	// Create dialer for unix socket
	dialer := func(ctx context.Context, addr string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, "unix", socketPath)
	}
	
	// Use passthrough resolver to bypass DNS lookup for unix sockets
	addr := "passthrough:///unix:" + socketPath
	conn, err := grpc.NewClient(addr, 
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithContextDialer(dialer))
	if err != nil {
		log.Fatalf("Failed to connect to SPIRE Server: %v", err)
	}
	defer conn.Close()
	log.Println("✓ Connected to SPIRE Server")

	// Step 4: Call BatchNewX509SVID API
	// Note: BatchNewX509SVID uses the EntryId to look up the registration entry.
	// The entry already contains the selectors (like UID) that were configured
	// when the entry was created. The UID is NOT automatically extracted from
	// the calling process - it comes from the registration entry.
	log.Println("Step 4: Calling BatchNewX509SVID API...")
	log.Printf("  Using EntryId: %s (selectors like UID come from this entry)", *entryID)
	client := svidv1.NewSVIDClient(conn)

	req := &svidv1.BatchNewX509SVIDRequest{
		Params: []*svidv1.NewX509SVIDParams{
			{
				EntryId:            *entryID,
				Csr:                csr,
				SovereignAttestation: sovereignAttestation,
			},
		},
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	resp, err := client.BatchNewX509SVID(ctx, req)
	if err != nil {
		log.Fatalf("Failed to call BatchNewX509SVID: %v", err)
	}

	if len(resp.Results) == 0 {
		log.Fatal("Error: No results returned from SPIRE Server")
	}

	result := resp.Results[0]
	if result.Status.Code != 0 {
		log.Fatalf("Error: SPIRE Server returned error: %s", result.Status.Message)
	}

	if result.Svid == nil {
		log.Fatal("Error: No SVID in response")
	}

	log.Println("✓ SVID generated successfully")

	// Step 5: Verify and save SVID
	log.Println("Step 5: Verifying and saving SVID...")

	// Parse certificate
	if len(result.Svid.CertChain) == 0 {
		log.Fatal("Error: Empty certificate chain")
	}

	cert, err := x509.ParseCertificate(result.Svid.CertChain[0])
	if err != nil {
		log.Fatalf("Failed to parse certificate: %v", err)
	}

	log.Printf("✓ SVID Details:")
	log.Printf("  - SPIFFE ID: %s", result.Svid.Id.String())
	log.Printf("  - Expires At: %s", time.Unix(result.Svid.ExpiresAt, 0).Format(time.RFC3339))
	log.Printf("  - Subject: %s", cert.Subject.String())
	log.Printf("  - Serial Number: %s", cert.SerialNumber.String())

	// Check for AttestedClaims
	if len(result.AttestedClaims) > 0 {
		log.Println("✓ AttestedClaims received:")
		claims := result.AttestedClaims[0]
		log.Printf("  - Geolocation: %s", claims.Geolocation)
		log.Printf("  - Host Integrity: %s", claims.HostIntegrityStatus.String())
		if claims.GpuMetricsHealth != nil {
			log.Printf("  - GPU Status: %s", claims.GpuMetricsHealth.Status)
			log.Printf("  - GPU Utilization: %.2f%%", claims.GpuMetricsHealth.UtilizationPct)
			log.Printf("  - GPU Memory: %d MB", claims.GpuMetricsHealth.MemoryMb)
		}
	} else {
		log.Println("⚠ No AttestedClaims in response (feature flag may be disabled)")
	}

	// Save certificate
	certPEM := pem.EncodeToMemory(&pem.Block{
		Type:  "CERTIFICATE",
		Bytes: result.Svid.CertChain[0],
	})
	if err := ioutil.WriteFile(*outputCert, certPEM, 0644); err != nil {
		log.Fatalf("Failed to save certificate: %v", err)
	}
	log.Printf("✓ Certificate saved to: %s", *outputCert)

	// Save AttestedClaims if present
	if len(result.AttestedClaims) > 0 {
		claimsJSON, err := json.MarshalIndent(result.AttestedClaims[0], "", "  ")
		if err == nil {
			attestedFile := strings.TrimSuffix(*outputCert, ".crt") + "_attested_claims.json"
			if err := ioutil.WriteFile(attestedFile, claimsJSON, 0644); err == nil {
				log.Printf("✓ AttestedClaims saved to: %s", attestedFile)
			}
		}
	}

	// Save private key
	keyDER, err := x509.MarshalPKCS8PrivateKey(privateKey)
	if err != nil {
		log.Fatalf("Failed to marshal private key: %v", err)
	}
	keyPEM := pem.EncodeToMemory(&pem.Block{
		Type:  "PRIVATE KEY",
		Bytes: keyDER,
	})
	if err := ioutil.WriteFile(*outputKey, keyPEM, 0600); err != nil {
		log.Fatalf("Failed to save private key: %v", err)
	}
	log.Printf("✓ Private key saved to: %s", *outputKey)

	log.Println("")
	log.Println("✅ Successfully generated SVID with SovereignAttestation!")
	log.Printf("   Certificate: %s", *outputCert)
	log.Printf("   Private Key: %s", *outputKey)
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// generateCSR creates a Certificate Signing Request with the specified SPIFFE ID
func generateCSR(spiffeIDStr string) ([]byte, interface{}, error) {
	id, err := spiffeid.FromString(spiffeIDStr)
	if err != nil {
		return nil, nil, fmt.Errorf("invalid SPIFFE ID: %w", err)
	}

	// Generate private key (ECDSA P-256)
	privateKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to generate private key: %w", err)
	}

	// Create CSR template
	template := &x509.CertificateRequest{
		Subject: pkix.Name{
			CommonName: "sovereign-workload",
		},
		URIs: []*url.URL{id.URL()},
	}

	// Create CSR
	csr, err := x509.CreateCertificateRequest(rand.Reader, template, privateKey)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to create CSR: %w", err)
	}

	return csr, privateKey, nil
}

// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// createStubbedSovereignAttestation creates a stubbed SovereignAttestation for Phase 1 testing
func createStubbedSovereignAttestation() *types.SovereignAttestation {
	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Create stubbed TPM quote (base64 encoded)
	stubbedTPMQuote := base64.StdEncoding.EncodeToString([]byte("stubbed-tpm-quote-for-phase1-testing"))

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Create stubbed app key public (PEM format)
	stubbedAppKeyPublic := `-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEStubbedAppKeyPublicKeyForPhase1Testing
-----END PUBLIC KEY-----`

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Create stubbed app key certificate (base64 encoded)
	stubbedAppKeyCert := base64.StdEncoding.EncodeToString([]byte("stubbed-app-key-certificate"))

	// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
	// Generate a nonce for freshness
	nonceBytes := make([]byte, 32)
	rand.Read(nonceBytes)
	nonce := base64.StdEncoding.EncodeToString(nonceBytes)

	return &types.SovereignAttestation{
		TpmSignedAttestation: stubbedTPMQuote,
		AppKeyPublic:         stubbedAppKeyPublic,
		AppKeyCertificate:    []byte(stubbedAppKeyCert),
		ChallengeNonce:       nonce,
		WorkloadCodeHash:     "stubbed-workload-code-hash-abc123",
	}
}
