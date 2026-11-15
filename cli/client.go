package main

import (
	"bytes"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
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
	// urlErr is the refusal of BANCO_URL, reported by the first request.
	urlErr error
}

// contractExempt are the commands that work when the CLI's contract differs from the server's (D-330): they are how
// an out-of-date CLI learns what changed and replaces itself, so they must never be refused for being out of date.
var contractExempt = map[string]bool{"token": true, "changes": true, "docs show": true, "self-update": true}

// do performs one authenticated request and returns the body of a 2xx answer.
// Every response must carry X-Banco-Contract equal to the embedded contract's
// digest, otherwise the CLI and the server disagree and the CLI refuses to go on
// (except for the commands of contractExempt).
func (c *client) do(command, method, path string) ([]byte, error) {
	return c.doBody(command, method, path, nil)
}

// doBody is do with a JSON request body (nil for none).
func (c *client) doBody(command, method, path string, payload []byte) ([]byte, error) {
	return c.doWith(command, method, path, payload, nil)
}

// doWith is doBody with extra request headers (X-Banco-Dry-Run).
func (c *client) doWith(command, method, path string, payload []byte, headers map[string]string) ([]byte, error) {
	resp, err := c.open(command, method, path, payload, headers)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, newErr(ExitServer, "E-NETWORK", "", err.Error(), "")
	}
	return body, nil
}

// refuseRedirect keeps every request on the address of BANCO_URL: a redirect is answered as it came (http.Client
// would otherwise follow it, and forward the Authorization header to the same host on another scheme or port).
func refuseRedirect(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }

// open performs one authenticated request and checks the answer (redirect, rate limit, contract header, status). On a
// 2xx it returns the response with its body still open for the caller to read and close; otherwise an error.
func (c *client) open(command, method, path string, payload []byte, headers map[string]string) (*http.Response, error) {
	if c.urlErr != nil {
		return nil, c.urlErr
	}
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

	hc := *c.http
	hc.CheckRedirect = refuseRedirect
	resp, err := hc.Do(req)
	if err != nil {
		return nil, newErr(ExitServer, "E-NETWORK", "", err.Error(), "banco health")
	}
	if resp.StatusCode >= 200 && resp.StatusCode <= 299 {
		if err := checkContract(command, resp); err != nil {
			resp.Body.Close()
			return nil, err
		}
		return resp, nil
	}
	defer resp.Body.Close()
	// An error answer is small; a larger one is cut, never read whole.
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, newErr(ExitServer, "E-NETWORK", "", err.Error(), "")
	}
	if resp.StatusCode >= 300 && resp.StatusCode <= 399 {
		return nil, newErr(ExitServer, "E-NETWORK", "", fmt.Sprintf("the server answered with a redirect (HTTP %d to %q); the CLI follows none, so the token goes nowhere else", resp.StatusCode, resp.Header.Get("Location")), "set BANCO_URL to the API address itself, for example https://api.banco.scc.im")
	}
	// The public edge's rate limit (Traefik, D-327: average 10 requests per second, burst 30 per client IP) answers 429
	// itself, without the contract header; banco's own 429 (E-VIEW-LIMIT, D-332) carries it and passes through below.
	if resp.StatusCode == http.StatusTooManyRequests && resp.Header.Get("X-Banco-Contract") == "" {
		return nil, newErr(ExitServer, "E-RATE-LIMIT", "", "the edge limits requests to an average of 10 per second (burst 30) per client IP", "wait 10 s, then send the request again")
	}
	// The server sends the contract digest only to a caller that holds a good token: a refused token is its own error.
	if resp.Header.Get("X-Banco-Contract") == "" && resp.StatusCode == http.StatusUnauthorized {
		return nil, errorFromBody(resp.StatusCode, body)
	}
	if err := checkContract(command, resp); err != nil {
		return nil, err
	}
	return nil, errorFromBody(resp.StatusCode, body)
}

// checkContract refuses an answer without the contract header (not a banco server) or, except for the commands of
// contractExempt, with another contract than the CLI's.
func checkContract(command string, resp *http.Response) error {
	got := resp.Header.Get("X-Banco-Contract")
	if got == "" {
		// No contract header: not a banco server answering (restarting, proxy error page).
		return newErr(ExitServer, "E-NETWORK", "", fmt.Sprintf("the server did not answer as banco (HTTP %d, no contract header); it may be restarting", resp.StatusCode), "retry in 60 s, then banco health")
	}
	if got != contract.Digest() && !contractExempt[command] {
		return newErr(ExitServer, "E-CONTRACT", "X-Banco-Contract",
			fmt.Sprintf("server contract %q differs from this CLI's %q", got, contract.Digest()),
			"banco self-update")
	}
	return nil
}

func newClient(getenv func(string) string) *client {
	base, urlErr := normalizeBaseURL(getenv("BANCO_URL"))
	return &client{baseURL: base, http: &http.Client{Timeout: 300 * time.Second, CheckRedirect: refuseRedirect}, tokens: defaultTokenSource(), session: getenv("BANCO_SESSION"), urlErr: urlErr}
}

// normalizeBaseURL reads BANCO_URL: http or https, a host with an optional port and an optional path prefix, no
// trailing slash. A bare host ("api.banco.scc.im") is https; a loopback address without a scheme is http.
func normalizeBaseURL(raw string) (string, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return defaultURL, nil
	}
	fail := func(message string) (string, error) {
		return defaultURL, newErr(ExitUsage, "E-URL", "BANCO_URL", message, "set BANCO_URL to the API address, for example https://api.banco.scc.im")
	}
	if !strings.Contains(raw, "://") {
		scheme := "https"
		host := raw
		if i := strings.IndexAny(host, "/?#"); i >= 0 {
			host = host[:i]
		}
		if h, _, err := net.SplitHostPort(host); err == nil {
			host = h
		}
		if host = strings.Trim(host, "[]"); host == "localhost" || net.ParseIP(host).IsLoopback() {
			scheme = "http"
		}
		raw = scheme + "://" + raw
	}
	u, err := url.Parse(raw)
	if err != nil {
		return fail(err.Error())
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return fail("BANCO_URL must start with http:// or https://, not " + u.Scheme + "://")
	}
	if u.Hostname() == "" {
		return fail("BANCO_URL has no host")
	}
	if u.User != nil || u.RawQuery != "" || u.Fragment != "" {
		return fail("BANCO_URL is the address of the server: no user, query or fragment")
	}
	// The Bearer token must never cross a network in clear (D-327): http is for the loopback listener only.
	if host := u.Hostname(); u.Scheme == "http" && host != "localhost" && !net.ParseIP(host).IsLoopback() {
		return fail("BANCO_URL uses http:// for " + host + ": the token would travel in clear; use https://, or http:// only for localhost and 127.0.0.1")
	}
	return u.Scheme + "://" + u.Host + strings.TrimRight(u.EscapedPath(), "/"), nil
}
