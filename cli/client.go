package main

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"time"

	"banco/contract"
)

const defaultURL = "http://127.0.0.1:3100"

// client talks to the API listener.
type client struct {
	baseURL string
	http    *http.Client
	tokens  tokenSource
	// session is the id of the working session (banco session new), sent as
	// X-Banco-Session on every request; the server asks for it where it matters.
	session string
}

// do performs one authenticated request and returns the body of a 2xx answer.
// Every response must carry X-Banco-Contract equal to the embedded contract's
// digest, otherwise the CLI and the server disagree and the CLI refuses to go on.
func (c *client) do(command, method, path string) ([]byte, error) {
	return c.doBody(command, method, path, nil)
}

// doBody is do with a JSON request body (nil for none).
func (c *client) doBody(command, method, path string, payload []byte) ([]byte, error) {
	return c.doWith(command, method, path, payload, nil)
}

// doWith is doBody with extra request headers (X-Banco-Dry-Run).
func (c *client) doWith(command, method, path string, payload []byte, headers map[string]string) ([]byte, error) {
	token, err := c.tokens.token(command)
	if err != nil {
		return nil, err
	}
	var reader io.Reader
	if payload != nil {
		reader = bytes.NewReader(payload)
	}
	req, err := http.NewRequest(method, c.baseURL+path, reader)
	if err != nil {
		return nil, newErr(ExitUsage, "E-URL", "BANCO_URL", err.Error(), "check BANCO_URL")
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Accept", "application/json")
	if payload != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if c.session != "" {
		req.Header.Set("X-Banco-Session", c.session)
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, newErr(ExitServer, "E-NETWORK", "", err.Error(), "banco health")
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, newErr(ExitServer, "E-NETWORK", "", err.Error(), "")
	}

	got := resp.Header.Get("X-Banco-Contract")
	if got == "" {
		// No contract header: not a banco server answering (restarting, proxy error page).
		return nil, newErr(ExitServer, "E-NETWORK", "", fmt.Sprintf("the server did not answer as banco (HTTP %d, no contract header); it may be restarting", resp.StatusCode), "retry in 60 s, then banco health")
	}
	if got != contract.Digest() {
		return nil, newErr(ExitServer, "E-CONTRACT", "X-Banco-Contract",
			fmt.Sprintf("server contract %q differs from this CLI's %q", got, contract.Digest()),
			"go build -o bin/banco ./cli")
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return nil, errorFromBody(resp.StatusCode, body)
	}
	return body, nil
}

func newClient(getenv func(string) string) *client {
	base := getenv("BANCO_URL")
	if base == "" {
		base = defaultURL
	}
	return &client{baseURL: base, http: &http.Client{Timeout: 300 * time.Second}, tokens: defaultTokenSource(), session: getenv("BANCO_SESSION")}
}
