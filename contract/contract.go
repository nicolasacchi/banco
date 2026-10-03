// Package contract embeds contract/commands.json, the one file shared by the
// Rails API (served at /api/v1/schema) and the Go CLI.
package contract

import (
	"crypto/sha256"
	_ "embed"
	"encoding/hex"
	"encoding/json"
)

//go:embed commands.json
var Raw []byte

// Command is one entry of the contract.
type Command struct {
	Name       string   `json:"name"`
	Local      bool     `json:"local"`
	Method     *string  `json:"method"`
	Path       *string  `json:"path"`
	Args       []string `json:"args"`
	Flags      []string `json:"flags,omitempty"`
	ErrorCodes []string `json:"error_codes"`
}

// Contract is the parsed commands.json.
type Contract struct {
	Version   int               `json:"contract_version"`
	ExitCodes map[string]string `json:"exit_codes"`
	Commands  []Command         `json:"commands"`
}

// Parse decodes the embedded contract.
func Parse() (Contract, error) {
	var c Contract
	err := json.Unmarshal(Raw, &c)
	return c, err
}

// Digest is the sha256 (hex) of the embedded file; the server sends the same
// value in X-Banco-Contract on every response.
func Digest() string {
	sum := sha256.Sum256(Raw)
	return hex.EncodeToString(sum[:])
}
