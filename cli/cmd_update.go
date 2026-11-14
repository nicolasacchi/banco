package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"runtime"

	"banco/contract"
)

// Staying current (D-330): the token as the server knows it, what changed in the software, the two docs the bot lives by,
// and the CLI's own update from the server's release build. These four commands work when the CLI's contract differs from
// the server's (contractExempt): they are how an out-of-date CLI catches up.

// updates is the answer of GET /api/v1/updates.
type updates struct {
	Server struct {
		Commit  string  `json:"commit"`
		BuiltAt *string `json:"built_at"`
	} `json:"server"`
	ContractDigest string `json:"contract_digest"`
	CLI            struct {
		Version *string   `json:"version"`
		Files   []cliFile `json:"files"`
	} `json:"cli"`
	Docs    []json.RawMessage `json:"docs"`
	Changes []json.RawMessage `json:"changes"`
}

// cliFile is one binary of the server's release build (dist/SHA256SUMS).
type cliFile struct {
	Name   string `json:"name"`
	OS     string `json:"os"`
	Arch   string `json:"arch"`
	SHA256 string `json:"sha256"`
	Size   int64  `json:"size"`
}

var decisionNumberRe = regexp.MustCompile(`^D-[0-9]{3,}$`)

// runToken prints the token of BANCO_TOKEN as the server knows it (GET /api/v1/token): role, teacher, effective expiry,
// whether it renews on use and its lifetime. Never the secret.
func runToken(e *env, args []string) error {
	fs := flag.NewFlagSet("token", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	if len(pos) != 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "token takes no argument", "banco token")
	}
	return send(e, "token", "GET", "/api/v1/token", nil, false)
}

// runChanges prints the decisions recorded after --since (all without it), oldest first, with the server's commit.
func runChanges(e *env, args []string) error {
	fs := flag.NewFlagSet("changes", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	since := fs.String("since", "", "the last decision already read, such as D-327")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco changes --since D-327"
	if len(pos) != 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "changes takes no positional argument", next)
	}
	path := "/api/v1/updates"
	if *since != "" {
		if !decisionNumberRe.MatchString(*since) {
			return newErr(ExitUsage, "E-USAGE", "since", "--since is a decision number such as D-327", next)
		}
		path += "?" + url.Values{"since": {*since}}.Encode()
	}
	u, err := fetchUpdates(e.client(), "changes", path)
	if err != nil {
		return err
	}
	out := map[string]any{"since": nil, "server_commit": u.Server.Commit, "changes": u.Changes}
	if *since != "" {
		out["since"] = *since
	}
	return json.NewEncoder(e.stdout).Encode(out)
}

// runDocsShow prints one of the docs the bot lives by (GET /api/v1/docs/:name): {name, sha256, text}.
func runDocsShow(e *env, args []string) error {
	fs := flag.NewFlagSet("docs show", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	if len(pos) != 1 || (pos[0] != "bot" && pos[0] != "api") {
		return newErr(ExitUsage, "E-USAGE", "name", "docs show takes bot (docs/bot.md) or api (docs/api.md)", "banco docs show bot")
	}
	return send(e, "docs show", "GET", "/api/v1/docs/"+pos[0], nil, false)
}

// runSelfUpdate compares this CLI with the server's release build and, unless --check, replaces its own executable with
// the build for this platform after checking its sha256. The new file is written next to the executable and renamed
// over it, so the old one stays whole until the new one is complete; on Windows, where a running program cannot be
// replaced, it is written as banco.new.exe beside it.
func runSelfUpdate(e *env, args []string) error {
	fs := flag.NewFlagSet("self-update", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	check := fs.Bool("check", false, "only say whether an update is available")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	if len(pos) != 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "self-update takes no positional argument", "banco self-update --check")
	}
	c := e.client()
	u, err := fetchUpdates(c, "self-update", "/api/v1/updates")
	if err != nil {
		return err
	}
	name := releaseName(runtime.GOOS, runtime.GOARCH)
	var file *cliFile
	for i := range u.CLI.Files {
		if u.CLI.Files[i].Name == name {
			file = &u.CLI.Files[i]
		}
	}
	serverVersion := ""
	if u.CLI.Version != nil {
		serverVersion = *u.CLI.Version
	}
	contractDiffers := u.ContractDigest != contract.Digest()
	outdated := contractDiffers || (serverVersion != "" && serverVersion != version)
	report := map[string]any{
		"cli_version":            version,
		"server_cli_version":     u.CLI.Version,
		"contract_sha256":        contract.Digest(),
		"server_contract_sha256": u.ContractDigest,
		"server_commit":          u.Server.Commit,
		"file":                   name,
		"file_available":         file != nil,
		"update_available":       outdated && file != nil,
		"updated":                false,
	}
	if *check || !outdated {
		if outdated && file != nil {
			report["next"] = "banco self-update"
		}
		return json.NewEncoder(e.stdout).Encode(report)
	}
	if file == nil {
		return newErr(ExitValidation, "E-NOT-FOUND", "file",
			fmt.Sprintf("this CLI is out of date and the server publishes no release build %s", name),
			"ask the operator to rebuild the image (bin/build-cli-dist runs in its Dockerfile)")
	}
	data, err := c.do("self-update", "GET", "/api/v1/cli/"+url.PathEscape(name))
	if err != nil {
		return err
	}
	sum := sha256.Sum256(data)
	if got := hex.EncodeToString(sum[:]); got != file.SHA256 || int64(len(data)) != file.Size {
		return newErr(ExitServer, "E-SELF-UPDATE", "sha256",
			fmt.Sprintf("the download of %s has sha256 %s and %d bytes, the server lists %s and %d bytes: nothing was replaced", name, got, len(data), file.SHA256, file.Size),
			"retry banco self-update; if it fails again, tell the operator")
	}
	exe, err := executablePath(e)
	if err != nil {
		return newErr(ExitServer, "E-SELF-UPDATE", "executable", "cannot find this program's file: "+err.Error()+"; nothing was replaced", "install the release by hand (docs/api.md «Staying current»)")
	}
	target, err := installBinary(exe, data, runtime.GOOS)
	if err != nil {
		return newErr(ExitServer, "E-SELF-UPDATE", "executable", "cannot write the new program next to "+exe+": "+err.Error()+"; nothing was replaced", "make that directory writable, or install the release by hand (docs/api.md «Staying current»)")
	}
	report["updated"] = true
	report["update_available"] = false
	report["path"] = target
	report["next"] = "banco changes --since <the last decision you read>, then banco docs show bot"
	if runtime.GOOS == "windows" {
		report["note"] = "Windows cannot replace a running program: the new one is " + target + "; when this command has ended, replace " + exe + " with it"
	}
	return json.NewEncoder(e.stdout).Encode(report)
}

// fetchUpdates reads GET /api/v1/updates (path may carry ?since=).
func fetchUpdates(c *client, command, path string) (updates, error) {
	var u updates
	body, err := c.do(command, "GET", path)
	if err != nil {
		return u, err
	}
	if err := json.Unmarshal(body, &u); err != nil {
		return u, newErr(ExitServer, "E-NETWORK", "", "the server's list of updates is not JSON: "+err.Error(), "retry in 60 s, then banco health")
	}
	return u, nil
}

// releaseName is the file name bin/build-cli-dist gives the binary of a platform.
func releaseName(goos, goarch string) string {
	name := "banco-" + goos + "-" + goarch
	if goos == "windows" {
		name += ".exe"
	}
	return name
}

// executablePath is the file of the running program, symlinks resolved, so that the real file is replaced.
func executablePath(e *env) (string, error) {
	find := e.executable
	if find == nil {
		find = os.Executable
	}
	exe, err := find()
	if err != nil {
		return "", err
	}
	return filepath.EvalSymlinks(exe)
}

// installBinary writes data to a temporary file in the directory of exe, makes it executable and renames it over exe
// (on Windows: over banco.new.exe beside it). A failure leaves exe untouched and removes the temporary file. It returns
// the path written.
func installBinary(exe string, data []byte, goos string) (string, error) {
	dir := filepath.Dir(exe)
	target := exe
	if goos == "windows" {
		target = filepath.Join(dir, "banco.new.exe")
	}
	tmp, err := os.CreateTemp(dir, ".banco-update-*")
	if err != nil {
		return "", err
	}
	done := false
	defer func() {
		if !done {
			tmp.Close()
			os.Remove(tmp.Name())
		}
	}()
	if _, err := tmp.Write(data); err != nil {
		return "", err
	}
	if err := tmp.Sync(); err != nil {
		return "", err
	}
	if err := tmp.Close(); err != nil {
		return "", err
	}
	if err := os.Chmod(tmp.Name(), 0o755); err != nil {
		return "", err
	}
	if err := os.Rename(tmp.Name(), target); err != nil {
		return "", err
	}
	done = true
	return target, nil
}
