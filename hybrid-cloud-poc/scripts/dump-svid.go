// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
// Script to dump SVID and highlight Phase 1 additions (AttestedClaims)

package main

import (
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"flag"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
	"google.golang.org/protobuf/encoding/protojson"
)

var (
	certPath       = flag.String("cert", "svid.crt", "Path to SVID certificate file")
	attestedPath   = flag.String("attested", "", "Path to AttestedClaims JSON file (optional)")
	format         = flag.String("format", "pretty", "Output format: pretty, json, or detailed")
	highlightColor = flag.Bool("color", true, "Enable color highlighting for Phase 1 additions")
)

const (
	colorReset  = "\033[0m"
	colorGreen  = "\033[32m"
	colorYellow = "\033[33m"
	colorBlue   = "\033[34m"
	colorCyan   = "\033[36m"
	colorBold   = "\033[1m"
)

func main() {
	flag.Parse()

	if *certPath == "" {
		fmt.Fprintf(os.Stderr, "Error: certificate path required\n")
		os.Exit(1)
	}

	// Read and parse certificate chain
	certs, err := readCertificates(*certPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error reading certificate: %v\n", err)
		os.Exit(1)
	}

	if len(certs) == 0 {
		fmt.Fprintf(os.Stderr, "Error: no certificates found in %s\n", *certPath)
		os.Exit(1)
	}

	// Read AttestedClaims if provided
	var attestedClaims *types.AttestedClaims
	if *attestedPath != "" {
		attestedClaims, err = readAttestedClaims(*attestedPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Warning: Could not read AttestedClaims: %v\n", err)
		}
	}

	// Output based on format
	switch *format {
	case "json":
		outputJSON(certs, attestedClaims)
	case "detailed":
		outputDetailed(certs, attestedClaims)
	default:
		outputPretty(certs, attestedClaims)
	}
}

func readCertificates(path string) ([]*x509.Certificate, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var certs []*x509.Certificate
	for len(data) > 0 {
		block, rest := pem.Decode(data)
		if block == nil {
			break
		}
		data = rest
		if block.Type != "CERTIFICATE" {
			continue
		}
		cert, err := x509.ParseCertificate(block.Bytes)
		if err != nil {
			return nil, err
		}
		certs = append(certs, cert)
	}

	if len(certs) == 0 {
		return nil, fmt.Errorf("failed to decode any certificates")
	}

	return certs, nil
}

func readAttestedClaims(path string) (*types.AttestedClaims, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var claims types.AttestedClaims
	err = protojson.Unmarshal(data, &claims)
	if err != nil {
		return nil, err
	}

	return &claims, nil
}

func outputPretty(certs []*x509.Certificate, claims *types.AttestedClaims) {
	cert := certs[0]

	fmt.Println("╔════════════════════════════════════════════════════════════════╗")
	fmt.Println("║              SPIFFE Verifiable Identity Document (SVID)        ║")
	fmt.Println("╚════════════════════════════════════════════════════════════════╝")
	fmt.Println()

	// Standard SVID Information
	fmt.Println("📋 Standard SVID Information:")
	fmt.Println(strings.Repeat("─", 70))
	printField("Subject", cert.Subject.String(), false)
	printField("Issuer", cert.Issuer.String(), false)
	printField("Serial Number", cert.SerialNumber.String(), false)
	printField("Valid From", cert.NotBefore.Format(time.RFC3339), false)
	printField("Valid Until", cert.NotAfter.Format(time.RFC3339), false)

	// SPIFFE ID
	spiffeID := extractSPIFFEID(cert)
	if spiffeID != "" {
		printField("SPIFFE ID", spiffeID, false)
	}

	// DNS Names and URIs
	if len(cert.DNSNames) > 0 {
		printField("DNS Names", strings.Join(cert.DNSNames, ", "), false)
	}
	if len(cert.URIs) > 0 {
		uris := make([]string, len(cert.URIs))
		for i, uri := range cert.URIs {
			uris[i] = uri.String()
		}
		printField("URIs", strings.Join(uris, ", "), false)
	}

	fmt.Println()

	// Phase 1 Additions (AttestedClaims)
	if claims != nil {
		fmt.Println()
		fmt.Println(colorize("🆕 Phase 1 Additions (Unified-Identity):", true, colorBold+colorGreen))
		fmt.Println(strings.Repeat("═", 70))
		fmt.Println()

		// Geolocation
		if claims.Geolocation != "" {
			printField("📍 Geolocation", claims.Geolocation, true)
		}

		// Host Integrity
		if claims.HostIntegrityStatus != types.AttestedClaims_HOST_INTEGRITY_UNSPECIFIED {
			integrityStatus := claims.HostIntegrityStatus.String()
			printField("🔒 Host Integrity Status", integrityStatus, true)
		}

		// GPU Metrics
		if claims.GpuMetricsHealth != nil {
			gpu := claims.GpuMetricsHealth
			fmt.Println(colorize("  🎮 GPU Metrics Health:", false, colorBold+colorCyan))
			if gpu.Status != "" {
				printField("    Status", gpu.Status, true)
			}
			if gpu.UtilizationPct > 0 {
				printField("    Utilization", fmt.Sprintf("%.2f%%", gpu.UtilizationPct), true)
			}
			if gpu.MemoryMb > 0 {
				printField("    Memory", fmt.Sprintf("%d MB", gpu.MemoryMb), true)
			}
		}

		fmt.Println()
		fmt.Println(strings.Repeat("─", 70))
		fmt.Println(colorize("✓ This SVID includes Phase 1 AttestedClaims (Unified-Identity)", false, colorGreen))
	} else {
		fmt.Println()
		fmt.Println(colorize("⚠ No AttestedClaims found (Phase 1 feature may be disabled)", false, colorYellow))
		fmt.Println("   To include AttestedClaims, ensure:")
		fmt.Println("   1. Unified-Identity feature flag is enabled")
		fmt.Println("   2. SovereignAttestation is provided in the request")
		fmt.Println("   3. Keylime stub is running and accessible")
	}

	fmt.Println()

	printCertificateChain(certs)
}

func outputDetailed(certs []*x509.Certificate, claims *types.AttestedClaims) {
	outputPretty(certs, claims)

	cert := certs[0]

	// Additional certificate details
	fmt.Println()
	fmt.Println("📊 Additional Certificate Details:")
	fmt.Println(strings.Repeat("─", 70))
	fmt.Printf("Key Usage: %v\n", cert.KeyUsage)
	fmt.Printf("Ext Key Usage: %v\n", cert.ExtKeyUsage)
	fmt.Printf("Signature Algorithm: %s\n", cert.SignatureAlgorithm)
	fmt.Printf("Public Key Algorithm: %s\n", cert.PublicKeyAlgorithm)
	fmt.Printf("Version: %d\n", cert.Version)

	// Certificate extensions
	if len(cert.Extensions) > 0 {
		fmt.Println()
		fmt.Println("Extensions:")
		for _, ext := range cert.Extensions {
			fmt.Printf("  OID: %s, Critical: %v\n", ext.Id, ext.Critical)
		}
	}
}

func outputJSON(certs []*x509.Certificate, claims *types.AttestedClaims) {
	cert := certs[0]

	output := map[string]interface{}{
		"svid": map[string]interface{}{
			"subject":       cert.Subject.String(),
			"issuer":        cert.Issuer.String(),
			"serial_number": cert.SerialNumber.String(),
			"valid_from":    cert.NotBefore.Format(time.RFC3339),
			"valid_until":   cert.NotAfter.Format(time.RFC3339),
			"spiffe_id":     extractSPIFFEID(cert),
			"dns_names":     cert.DNSNames,
			"uris":          certURIsToStrings(cert),
		},
	}

	var chainDetails []map[string]interface{}
	for idx, chainCert := range certs {
		spiffeID := extractSPIFFEID(chainCert)
		role, _ := describeCertificate(idx, chainCert, spiffeID)
		chainDetails = append(chainDetails, map[string]interface{}{
			"index":      idx,
			"role":       role,
			"subject":    chainCert.Subject.String(),
			"issuer":     chainCert.Issuer.String(),
			"spiffe_id":  spiffeID,
			"not_after":  chainCert.NotAfter.Format(time.RFC3339),
			"is_ca":      chainCert.IsCA,
			"chain_size": len(certs),
		})
	}
	output["certificate_chain"] = chainDetails

	if claims != nil {
		claimsJSON, _ := protojson.Marshal(claims)
		var claimsMap map[string]interface{}
		json.Unmarshal(claimsJSON, &claimsMap)
		output["attested_claims"] = claimsMap
		output["phase_1_enabled"] = true
	} else {
		output["phase_1_enabled"] = false
	}

	jsonData, _ := json.MarshalIndent(output, "", "  ")
	fmt.Println(string(jsonData))
}

func printField(label, value string, isPhase1 bool) {
	prefix := "  "
	if isPhase1 {
		prefix = colorize("  ➕ ", true, colorGreen)
	}
	fmt.Printf("%s%s: %s\n", prefix, label, value)
}

func extractSPIFFEID(cert *x509.Certificate) string {
	for _, uri := range cert.URIs {
		if strings.HasPrefix(uri.String(), "spiffe://") {
			return uri.String()
		}
	}
	return ""
}

func certURIsToStrings(cert *x509.Certificate) []string {
	result := make([]string, len(cert.URIs))
	for i, uri := range cert.URIs {
		result[i] = uri.String()
	}
	return result
}

func colorize(text string, bold bool, color string) string {
	if !*highlightColor {
		return text
	}
	if bold {
		return color + colorBold + text + colorReset
	}
	return color + text + colorReset
}

func describeCertificate(index int, cert *x509.Certificate, spiffeID string) (string, string) {
	if index == 0 {
		return "Workload SVID (leaf)", colorCyan
	}
	if spiffeID != "" && strings.Contains(spiffeID, "/spire/agent/") {
		return "Agent SVID (policy enforcement)", colorGreen
	}
	if spiffeID != "" {
		return "SPIFFE identity", colorBlue
	}
	if cert.IsCA {
		return "CA certificate", ""
	}
	return "Certificate", ""
}

func printCertificateChain(certs []*x509.Certificate) {
	fmt.Println("Certificate Chain Summary:")
	fmt.Println(strings.Repeat("─", 70))
	for idx, chainCert := range certs {
		spiffeID := extractSPIFFEID(chainCert)
		role, color := describeCertificate(idx, chainCert, spiffeID)
		label := fmt.Sprintf("[%d] %s", idx, role)
		if color != "" {
			label = colorize(label, true, color)
		}
		fmt.Println(label)
		fmt.Printf("    Subject: %s\n", chainCert.Subject.String())
		if spiffeID != "" {
			fmt.Printf("    SPIFFE ID: %s\n", spiffeID)
		} else {
			fmt.Println("    SPIFFE ID: (none)")
		}
		fmt.Printf("    Issuer: %s\n", chainCert.Issuer.String())
		fmt.Printf("    Expires: %s\n", chainCert.NotAfter.Format(time.RFC3339))
		fmt.Println()
	}
}
