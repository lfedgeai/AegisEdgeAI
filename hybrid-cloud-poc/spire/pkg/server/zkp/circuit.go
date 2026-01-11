package zkp

import (
	"fmt"

	"github.com/consensys/gnark-crypto/ecc"
	"github.com/consensys/gnark/backend/groth16"
	"github.com/consensys/gnark/constraint"
	"github.com/consensys/gnark/frontend"
	"github.com/consensys/gnark/frontend/cs/r1cs"
)

// SovereignReceiptCircuit defines the ZKP circuit for proving location proximity.
// For this POC, we prove that the private (Lat, Long) is within a square of
// size 2*Radius centered at (TowerLat, TowerLong).
// All values should be multiplied by 1,000,000 to handle 6 decimal places as integers.
type SovereignReceiptCircuit struct {
	// Private inputs
	Latitude  frontend.Variable `gnark:",private"`
	Longitude frontend.Variable `gnark:",private"`

	// Public inputs
	TowerLat  frontend.Variable `gnark:",public"`
	TowerLong frontend.Variable `gnark:",public"`
	Radius    frontend.Variable `gnark:",public"`
}

// Define the circuit constraints
func (c *SovereignReceiptCircuit) Define(api frontend.API) error {
	// 1. Latitude check
	// |Lat - TowerLat| <= Radius  =>  (Lat - TowerLat)^2 <= Radius^2
	diffLat := api.Sub(c.Latitude, c.TowerLat)
	sqDiffLat := api.Mul(diffLat, diffLat)
	sqRadius := api.Mul(c.Radius, c.Radius)
	api.AssertIsLessOrEqual(sqDiffLat, sqRadius)

	// 2. Longitude check
	// |Long - TowerLong| <= Radius  =>  (Long - TowerLong)^2 <= Radius^2
	diffLong := api.Sub(c.Longitude, c.TowerLong)
	sqDiffLong := api.Mul(diffLong, diffLong)
	api.AssertIsLessOrEqual(sqDiffLong, sqRadius)

	return nil
}

// CompileCircuit compiles the R1CS, and generates proving and verifying keys.
// In a real system, these would be generated once and shared.
func CompileCircuit() (groth16.ProvingKey, groth16.VerifyingKey, constraint.ConstraintSystem, error) {
	var circuit SovereignReceiptCircuit
	ccs, err := frontend.Compile(ecc.BN254.ScalarField(), r1cs.NewBuilder, &circuit)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("failed to compile circuit: %w", err)
	}

	pk, vk, err := groth16.Setup(ccs)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("failed to setup keys: %w", err)
	}

	return pk, vk, ccs, nil
}
