package main

import (
	"context"
	"os"
	"os/exec"
	"strings"
	"time"
)

// tokenSource resolves the agent token (D-05): BANCO_TOKEN if set, otherwise a
// pass-cli read per call with a 5 s timeout. The token lives in memory only.
type tokenSource struct {
	getenv func(string) string
	// run executes a command and returns its stdout; replaced in tests.
	run func(ctx context.Context, env []string, name string, args ...string) ([]byte, error)
}

func defaultTokenSource() tokenSource {
	return tokenSource{getenv: os.Getenv, run: func(ctx context.Context, env []string, name string, args ...string) ([]byte, error) {
		cmd := exec.CommandContext(ctx, name, args...)
		cmd.Env = append(os.Environ(), env...)
		return cmd.Output()
	}}
}

func (t tokenSource) token(command string) (string, error) {
	if v := strings.TrimSpace(t.getenv("BANCO_TOKEN")); v != "" {
		return v, nil
	}
	kind := t.getenv("BANCO_AGENT_KIND")
	if kind == "" {
		kind = "claude"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	out, err := t.run(ctx, []string{"PROTON_PASS_AGENT_REASON=banco " + command},
		"pass-cli", "item", "view", "--vault-name", "Banco",
		"--item-title", "banco-agent-"+kind, "--field", "token")
	v := strings.TrimSpace(string(out))
	if err != nil || v == "" {
		return "", newErr(ExitAuth, "E-TOKEN", "BANCO_TOKEN",
			"no agent token: BANCO_TOKEN is not set and pass-cli could not read it", "pass-cli info")
	}
	return v, nil
}
