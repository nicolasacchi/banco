package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"banco/contract"
)

// captureServer answers a simulation and keeps what the CLI sent.
type captured struct {
	method, path, auth, ctype string
	body                      map[string]any
}

func captureServer(t *testing.T, status int, answer string) (*httptest.Server, *captured) {
	t.Helper()
	got := &captured{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got.method, got.path, got.auth, got.ctype = r.Method, r.URL.Path, r.Header.Get("Authorization"), r.Header.Get("Content-Type")
		raw, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(raw, &got.body)
		w.Header().Set("X-Banco-Contract", contract.Digest())
		w.WriteHeader(status)
		_, _ = w.Write([]byte(answer))
	}))
	t.Cleanup(srv.Close)
	return srv, got
}

func writeTemp(t *testing.T, name, content string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(p, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestDiagnosisSimulateSendsBundleAndNamedScript(t *testing.T) {
	srv, got := captureServer(t, 200, `{"end_reason":"frontier_empty","dry_run":true}`)
	file := writeTemp(t, "bp.json", `{"blueprint":{"subject":"math"},"graph":{"skills":[]}}`)
	r := runCLI(t, srv.URL, envToken("bnc_x"), "diagnosis", "simulate", "--blueprint", file, "--script", "all-wrong", "--json")
	if r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	if got.method != "POST" || got.path != "/api/v1/diagnosis/simulate" || got.ctype != "application/json" || got.auth != "Bearer bnc_x" {
		t.Errorf("request = %+v", got)
	}
	if got.body["script"] != "all-wrong" {
		t.Errorf("script = %v", got.body["script"])
	}
	bundle, _ := got.body["bundle"].(map[string]any)
	if bundle["blueprint"] == nil || bundle["graph"] == nil {
		t.Errorf("bundle = %v", got.body["bundle"])
	}
	var out map[string]any
	if err := json.Unmarshal([]byte(r.stdout), &out); err != nil || out["end_reason"] != "frontier_empty" {
		t.Errorf("stdout = %q (%v)", r.stdout, err)
	}
}

func TestDiagnosisSimulateScriptFileAndSubject(t *testing.T) {
	srv, got := captureServer(t, 200, `{}`)
	script := writeTemp(t, "script.json", `{"default":{"verdict":"correct"},"seconds":20}`)
	r := runCLI(t, srv.URL, envToken("bnc_x"), "diagnosis", "simulate", "--subject", "math", "--script", script)
	if r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	if got.body["subject"] != "math" || got.body["bundle"] != nil {
		t.Errorf("body = %v", got.body)
	}
	doc, _ := got.body["script"].(map[string]any)
	if doc["seconds"] != float64(20) {
		t.Errorf("script = %v", got.body["script"])
	}
}

func TestDiagnosisSimulateUsage(t *testing.T) {
	file := writeTemp(t, "bp.json", `{}`)
	for _, args := range [][]string{
		{"diagnosis", "simulate"},
		{"diagnosis", "simulate", "--blueprint", file, "--subject", "math"},
		{"diagnosis", "simulate", "--blueprint", file, "extra"},
		{"diagnosis", "simulate", "--blueprint", filepath.Join(t.TempDir(), "missing.json")},
		{"diagnosis", "simulate", "--blueprint", file, "--script", filepath.Join(t.TempDir(), "missing.json")},
	} {
		r := runCLI(t, "http://127.0.0.1:1", envToken("bnc_x"), args...)
		if r.exit != ExitUsage {
			t.Errorf("%v: exit %d, want %d (%s)", args, r.exit, ExitUsage, r.stderr)
		}
		assertErrJSON(t, r.stderr, "E-USAGE")
	}
}

func TestDiagnosisSimulateFileThatIsNotJSON(t *testing.T) {
	file := writeTemp(t, "bp.json", `{nope`)
	r := runCLI(t, "http://127.0.0.1:1", envToken("bnc_x"), "diagnosis", "simulate", "--blueprint", file)
	if r.exit != ExitValidation {
		t.Fatalf("exit %d", r.exit)
	}
	assertErrJSON(t, r.stderr, "E-SIMULATE-INPUT")
}

func TestDiagnosisSimulateServerRefusals(t *testing.T) {
	file := writeTemp(t, "bp.json", `{"subject":"math"}`)
	cases := []struct {
		status int
		code   string
		exit   int
	}{{422, "E-SIMULATE-INPUT", ExitValidation}, {422, "E-GRAPH-CYCLE", ExitValidation}, {404, "E-BLUEPRINT-UNKNOWN", ExitValidation}, {401, "E-AUTH", ExitAuth}}
	for _, c := range cases {
		srv, _ := captureServer(t, c.status, `{"code":"`+c.code+`","field":"blueprint","message":"m","next":"n"}`)
		r := runCLI(t, srv.URL, envToken("bnc_x"), "diagnosis", "simulate", "--blueprint", file)
		if r.exit != c.exit {
			t.Errorf("%s: exit %d, want %d", c.code, r.exit, c.exit)
		}
		assertErrJSON(t, r.stderr, c.code)
	}
}

func TestContractListsDiagnosisSimulate(t *testing.T) {
	c, err := contract.Parse()
	if err != nil {
		t.Fatal(err)
	}
	for _, cmd := range c.Commands {
		if cmd.Name == "diagnosis simulate" {
			if cmd.Local || cmd.Method == nil || *cmd.Method != "POST" || cmd.Path == nil || !strings.HasSuffix(*cmd.Path, "/diagnosis/simulate") {
				t.Fatalf("bad contract row: %+v", cmd)
			}
			return
		}
	}
	t.Fatal("diagnosis simulate is not in the contract")
}

// reportDoc is the typed shape of banco.diagnosis_report/1 (B-09). Decoding the
// Rails example with DisallowUnknownFields makes a new or renamed member of the
// report a failure here until the shape is updated on purpose: the golden test.
// The formula sheet as a declared support (D-216): counts of answered attempts per skill and per subject.
type formulaSheetCounts struct {
	Attempts  int `json:"attempts"`
	Available int `json:"available"`
	Opened    int `json:"opened"`
}

type reportDoc struct {
	Schema           string `json:"schema"`
	RulesVersion     string `json:"rules_version"`
	EngineVersion    string `json:"engine_version"`
	SittingCondition string `json:"sitting_condition"`
	Released         bool   `json:"released"`
	Subjects         []struct {
		Subject   string `json:"subject"`
		NameIt    string `json:"name_it"`
		Status    string `json:"status"`
		GraphForm string `json:"graph_form"`
		EntryTest struct {
			BlueprintRevisionID *int   `json:"blueprint_revision_id"`
			Seq                 *int   `json:"seq"`
			Approved            bool   `json:"approved"`
			ApprovedRevisionID  *int   `json:"approved_revision_id"`
			PendingRevision     bool   `json:"pending_revision"`
			NotMeasuredIt       string `json:"not_measured_it"`
			Calculator          string `json:"calculator"`
			Budget              struct {
				SittingMinutes int `json:"sitting_minutes"`
				Sittings       int `json:"sittings"`
			} `json:"budget"`
			DependsOnSubjects []string `json:"depends_on_subjects"`
			KindOverrides     []struct {
				Skill    string `json:"skill"`
				Kind     string `json:"kind"`
				ReasonIt string `json:"reason_it"`
			} `json:"kind_overrides"`
		} `json:"entry_test"`
		Run *struct {
			ID             int     `json:"id"`
			Sequence       int     `json:"sequence"`
			RulesVersion   string  `json:"rules_version"`
			EngineVersion  string  `json:"engine_version"`
			Closed         bool    `json:"closed"`
			EndReason      *string `json:"end_reason"`
			WaitingOn      *string `json:"waiting_on"`
			Served         int     `json:"served"`
			GraderVersions []struct {
				Grader        string `json:"grader"`
				GraderVersion string `json:"grader_version"`
			} `json:"grader_versions"`
		} `json:"run"`
		Sittings []struct {
			Index          int     `json:"index"`
			StartedAt      *string `json:"started_at"`
			ClosedAt       *string `json:"closed_at"`
			CloseReason    *string `json:"close_reason"`
			Served         int     `json:"served"`
			Condition      string  `json:"condition"`
			CountedMinutes int     `json:"counted_minutes"`
		} `json:"sittings"`
		CountedMinutes int            `json:"counted_minutes"`
		Groups         map[string]int `json:"groups"`
		Skills         []struct {
			Skill        string             `json:"skill"`
			LabelIt      string             `json:"label_it"`
			State        string             `json:"state"`
			Reason       *string            `json:"reason"`
			Group        string             `json:"group"`
			Scope        string             `json:"scope"`
			Kind         string             `json:"kind"`
			Guest        *string            `json:"guest"`
			Evidence     []string           `json:"evidence"`
			Served       int                `json:"served"`
			ErrorCodes   []string           `json:"error_codes"`
			Unclassified bool               `json:"unclassified"`
			FormulaSheet formulaSheetCounts `json:"formula_sheet"`
			Marks        []string           `json:"marks"`
			Lines        struct {
				Prima   []json.RawMessage `json:"prima"`
				Seconda []json.RawMessage `json:"seconda"`
			} `json:"lines"`
		} `json:"skills"`
		ErrorsObserved []struct {
			Skill           string `json:"skill"`
			Code            string `json:"code"`
			Count           int    `json:"count"`
			ExampleAttempts []int  `json:"example_attempts"`
		} `json:"errors_observed"`
		Unclassified []string `json:"unclassified"`
		Pending      []struct {
			Skill  string `json:"skill"`
			Reason string `json:"reason"`
		} `json:"pending"`
		Signals struct {
			SittingCondition string   `json:"sitting_condition"`
			RapidShare       float64  `json:"rapid_share"`
			DontKnowShare    float64  `json:"dont_know_share"`
			DontKnowCount    int      `json:"dont_know_count"`
			Answers          int      `json:"answers"`
			PendingAnswers   int      `json:"pending_answers"`
			Flags            []string `json:"flags"`
		} `json:"signals"`
		Checks       []json.RawMessage `json:"checks"`
		FormulaSheet struct {
			formulaSheetCounts
			Enabled bool     `json:"enabled"`
			Marks   []string `json:"marks"`
		} `json:"formula_sheet"`
	} `json:"subjects"`
}

func TestDiagnosisReportGolden(t *testing.T) {
	raw, err := os.ReadFile("../contract/examples/diagnosis-report.completed.json")
	if err != nil {
		t.Fatal(err)
	}
	var ex struct {
		Response struct {
			Body json.RawMessage `json:"body"`
		} `json:"response"`
	}
	if err := json.Unmarshal(raw, &ex); err != nil {
		t.Fatal(err)
	}
	srv, got := captureServer(t, 200, string(ex.Response.Body))
	r := runCLI(t, srv.URL, envToken("bnc_x"), "diagnosis", "report", "--subject", "math", "--json")
	if r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	if got.method != "GET" || got.path != "/api/v1/diagnosis/report" || got.auth != "Bearer bnc_x" {
		t.Errorf("request = %+v", got)
	}
	dec := json.NewDecoder(strings.NewReader(r.stdout))
	dec.DisallowUnknownFields()
	var doc reportDoc
	if err := dec.Decode(&doc); err != nil {
		t.Fatalf("the report no longer has the B-09 shape: %v", err)
	}
	if doc.Schema != "banco.diagnosis_report/1" || doc.SittingCondition != "unsupervised" || len(doc.Subjects) != 1 {
		t.Fatalf("report = %+v", doc)
	}
	s := doc.Subjects[0]
	if s.Subject != "math" || s.Status != "completed" || s.Run == nil || len(s.Sittings) == 0 || s.Sittings[0].Condition != "unsupervised" {
		t.Errorf("subject = %+v", s)
	}
	total := 0
	for _, n := range s.Groups {
		total += n
	}
	if total != len(s.Skills) {
		t.Errorf("groups add up to %d, skills are %d", total, len(s.Skills))
	}
	for _, e := range s.ErrorsObserved {
		if e.Count < 1 {
			t.Errorf("error %+v has no count", e)
		}
	}
}

func TestDiagnosisReportSubjectIsChecked(t *testing.T) {
	srv, got := captureServer(t, 200, `{}`)
	r := runCLI(t, srv.URL, envToken("bnc_x"), "diagnosis", "report", "--subject", "Math!")
	if r.exit != ExitUsage || got.path != "" {
		t.Errorf("exit %d, request %+v", r.exit, got)
	}
	r = runCLI(t, srv.URL, envToken("bnc_x"), "diagnosis", "report")
	if r.exit != ExitOK || got.path != "/api/v1/diagnosis/report" {
		t.Errorf("exit %d, request %+v", r.exit, got)
	}
}

func TestDiagnosisReportStudentKey(t *testing.T) {
	var rawQuery string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rawQuery = r.URL.RawQuery
		w.Header().Set("X-Banco-Contract", contract.Digest())
		_, _ = w.Write([]byte(`{}`))
	}))
	t.Cleanup(srv.Close)
	r := runCLI(t, srv.URL, envToken("bnc_x"), "diagnosis", "report", "--subject", "math", "--student", "trial-1")
	if r.exit != ExitOK || rawQuery != "student=trial-1&subject=math" {
		t.Errorf("exit %d, query %q, stderr %q", r.exit, rawQuery, r.stderr)
	}
	r = runCLI(t, srv.URL, envToken("bnc_x"), "diagnosis", "report", "--student", "trial-1")
	if r.exit != ExitOK || rawQuery != "student=trial-1" {
		t.Errorf("exit %d, query %q", r.exit, rawQuery)
	}
	rawQuery = ""
	r = runCLI(t, srv.URL, envToken("bnc_x"), "diagnosis", "report", "--student", "Trial 1!")
	if r.exit != ExitUsage || rawQuery != "" {
		t.Errorf("exit %d, query %q", r.exit, rawQuery)
	}
}

func TestHealthPrintsTheReportAndSkipsChromeOnRequest(t *testing.T) {
	srv, got := captureServer(t, 200, `{"ok":true,"db":"ok"}`)
	r := runCLI(t, srv.URL, envToken("bnc_x"), "health", "--no-chrome", "--json")
	if r.exit != ExitOK || got.path != "/api/v1/health" || !strings.Contains(r.stdout, `"ok":true`) {
		t.Errorf("exit %d, request %+v, stdout %q", r.exit, got, r.stdout)
	}
}
