package zkp

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"sync"

	"github.com/consensys/gnark-crypto/ecc"
	"github.com/consensys/gnark/backend/groth16"
	"github.com/consensys/gnark/constraint"
	"github.com/consensys/gnark/frontend"
)

// Prover manages the ZKP lifecycle
type Prover struct {
	pk  groth16.ProvingKey
	vk  groth16.VerifyingKey
	ccs constraint.ConstraintSystem
}

var (
	instance *Prover
	once     sync.Once
	initErr  error
)

// GetProver returns the singleton prover instance, initializing it if necessary
func GetProver() (*Prover, error) {
	once.Do(func() {
		pk, vk, ccs, err := CompileCircuit()
		if err != nil {
			initErr = err
			return
		}
		instance = &Prover{
			pk:  pk,
			vk:  vk,
			ccs: ccs,
		}
	})
	return instance, initErr
}

// GenerateReceipt generates a ZK proof of proximity and returns a base64-encoded receipt
func (p *Prover) GenerateReceipt(lat, long, tlat, tlong, radius float64) (string, error) {
	// 1. Convert to fixed-point integers (6 decimal places for precision)
	const scaling = 1000000.0

	assignment := SovereignReceiptCircuit{
		Latitude:  int64(lat * scaling),
		Longitude: int64(long * scaling),
		TowerLat:  int64(tlat * scaling),
		TowerLong: int64(tlong * scaling),
		Radius:    int64(radius * scaling),
	}

	// 2. Create witness
	witness, err := frontend.NewWitness(&assignment, ecc.BN254.ScalarField())
	if err != nil {
		return "", fmt.Errorf("failed to create witness: %w", err)
	}

	// 3. Generate proof
	proof, err := groth16.Prove(p.ccs, p.pk, witness)
	if err != nil {
		return "", fmt.Errorf("failed to generate proof: %w", err)
	}

	// 4. Serialize proof for inclusion in SVID claim
	var buf bytes.Buffer
	_, err = proof.WriteTo(&buf)
	if err != nil {
		return "", fmt.Errorf("failed to serialize proof: %w", err)
	}

	return base64.StdEncoding.EncodeToString(buf.Bytes()), nil
}

// VerifyReceipt verifies a ZK proof against public inputs
func (p *Prover) VerifyReceipt(proofB64 string, tlat, tlong, radius float64) (bool, error) {
	proofBytes, err := base64.StdEncoding.DecodeString(proofB64)
	if err != nil {
		return false, fmt.Errorf("failed to decode proof: %w", err)
	}

	proof := groth16.NewProof(ecc.BN254)
	_, err = proof.ReadFrom(bytes.NewReader(proofBytes))
	if err != nil {
		return false, fmt.Errorf("failed to read proof: %w", err)
	}

	// Public witness only
	const scaling = 1000000.0
	publicAssignment := SovereignReceiptCircuit{
		TowerLat:  int64(tlat * scaling),
		TowerLong: int64(tlong * scaling),
		Radius:    int64(radius * scaling),
	}

	publicWitness, err := frontend.NewWitness(&publicAssignment, ecc.BN254.ScalarField(), frontend.PublicOnly())
	if err != nil {
		return false, fmt.Errorf("failed to create public witness: %w", err)
	}

	err = groth16.Verify(proof, p.vk, publicWitness)
	if err != nil {
		return false, nil // Verification failed
	}

	return true, nil
}
