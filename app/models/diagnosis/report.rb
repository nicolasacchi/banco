module Diagnosis
  # The per-subject report of the diagnosis (B-09), format banco.diagnosis_report/1.
  # Read-only: nothing here writes a row, and the agent's API serves it as it is
  # (`banco diagnosis report --json`). The teacher's page renders the same hash.
  #
  # Per subject: which entry test was used, the state of the subject, the shape of
  # the graph, the sittings with the minutes counted, each skill with its state and
  # reason, the typical errors seen with counts, what waits for a correction, and the
  # signals the software cannot judge (rapid answers, "Non lo so" share, and the
  # condition of the sitting: always unsupervised, operator Q4).
  #
  # with_answers: false (the API) leaves the student's own words out: the content
  # agent may run on a model that is not the grader's provider (operator Q8), so the
  # JSON names the attempts and the page of the teacher shows their text.
  class Report
    SCHEMA = "banco.diagnosis_report/1".freeze
    STATUSES = %w[not_started in_progress paused continue_next_day completed to_redo].freeze
    RAPID_FACTOR = 0.2
    RAPID_FLAG_SHARE = 0.2
    DONT_KNOW_FLAG_SHARE = 0.5
    EXAMPLES = 3
    SITTING_CONDITION = "unsupervised".freeze
    GROUPS = %w[demonstrated to_recover to_learn not_assessed pending].freeze

    def self.call(subject: nil, with_answers: false)
      subjects = subject ? Array(subject) : Subject.order(:position).to_a
      student = Student.find_by(key: "student")
      {
        schema: SCHEMA, rules_version: Rules::V1::RULES_VERSION, engine_version: Engine::VERSION,
        sitting_condition: SITTING_CONDITION, released: Release.open?,
        subjects: subjects.map { |s| new(s, student, with_answers: with_answers).to_h }
      }
    end

    def initialize(subject, student, with_answers: false)
      @subject = subject
      @student = student
      @with_answers = with_answers
      @run = student && DiagnosisRun.where(student: student, subject: subject).order(:sequence).last
    end

    def to_h
      base = { subject: @subject.key, name_it: @subject.name_it, status: status, graph_form: graph_form, entry_test: entry_test }
      return base.merge(run: nil, sittings: [], counted_minutes: 0, groups: zero_groups, skills: [], errors_observed: [], unclassified: [],
                        pending: [], signals: signals_for(nil, [], 0), checks: []) unless @run

      base.merge(run: run_info, sittings: sittings, counted_minutes: (result[:counted_seconds] / 60.0).round, groups: groups,
                 skills: skills, errors_observed: errors_observed, unclassified: skills.select { |s| s[:unclassified] }.map { |s| s[:skill] },
                 pending: pending, signals: signals, checks: result[:checks])
    end

    private

    def voided? = @run && EventLoader.voided?(@run)

    def conductor = @conductor ||= Conductor.new(@run)

    def result = @result ||= Derivation.result(conductor.plan, EventLoader.for_run(@run), voided: voided?)

    def status
      return "not_started" unless @run
      return "to_redo" if voided?

      state = conductor.state
      return "completed" if state.closed || (!state.open_serve && conductor.holding?)
      return "paused" if state.open_sitting && paused?
      return "in_progress" if state.open_sitting
      return "continue_next_day" if state.sittings.any?

      "not_started"
    end

    def paused?
      @run.events.where(kind: %w[paused resumed]).order(:seq).last&.kind == "paused"
    end

    # A graph with no prerequisite edge at all is a flat list: the test has a fixed form.
    def graph_form
      graph = graph_body or return "adaptive"
      graph["skills"].any? { |s| Array(s["prerequisites"]).any? || Array(s["composite_of"]).any? } ? "adaptive" : "fixed_form"
    end

    def graph_body
      revision = @run ? @run.blueprint_revision.skill_graph_revision : SubjectStage.approved_graph(@subject)
      revision && JSON.parse(revision.body_json)
    end

    def entry_test
      used = @run&.blueprint_revision || Conductor.approved_blueprint(@subject)
      approved = SubjectStage.approved_blueprint(@subject)
      latest = Conductor.latest_blueprint(@subject)
      return { blueprint_revision_id: nil, seq: nil, approved: false, pending_revision: !latest.nil? } unless used

      { blueprint_revision_id: used.id, seq: used.seq, approved: !approved.nil?, approved_revision_id: approved&.id,
        pending_revision: !latest.nil? && !approved.nil? && latest.id != approved.id }.merge(test_settings(used)).compact
    end

    # What the author declared about the test itself (D-101): what it does not measure,
    # calculator, budget, other subjects it needs, and the kind overrides with reasons.
    def test_settings(revision)
      body = JSON.parse(revision.body_json)
      { not_measured_it: body["not_measured_it"], calculator: body["calculator"], budget: body["budget"],
        depends_on_subjects: body["depends_on_subjects"], kind_overrides: body["kind_overrides"] }
    end

    def run_info
      { id: @run.id, sequence: @run.sequence, rules_version: @run.rules_version, engine_version: @run.engine_version,
        closed: result[:closed], end_reason: result[:end_reason], waiting_on: result[:waiting_on], served: result[:served],
        grader_versions: AttemptGrading.where(attempt_id: attempts.map(&:id)).distinct.order(:grader, :grader_version).pluck(:grader, :grader_version).map { |g, v| { grader: g, grader_version: v } } }
    end

    def sittings
      result[:sittings].map { |s| s.merge(counted_minutes: (s[:counted_seconds] / 60.0).round).except(:counted_seconds) }
    end

    # ---- skills

    def own_rows = @own_rows ||= result[:skills].select { |r| r[:subject] == @subject.key || r[:guest] }

    def skills
      @skills ||= own_rows.map do |row|
        { skill: row[:skill], label_it: labels[row[:skill]] || row[:skill], state: row[:state], reason: row[:reason], group: group_of(row),
          scope: row[:scope], kind: row[:kind], guest: row[:guest], evidence: row[:evidence], served: row[:served],
          error_codes: row[:error_codes], unclassified: row[:unclassified], lines: lines_of(row[:skill]) }.compact
      end
    end

    def group_of(row)
      return "demonstrated" if row[:state] == "demonstrated"
      return "pending" if row[:state] == "pending"
      return "to_learn" if row[:kind] == "learn" && (row[:state] == "to_recover" || row[:reason] == "prerequisite_to_recover")
      return "to_recover" if row[:state] == "to_recover"

      "not_assessed"
    end

    def groups = GROUPS.to_h { |g| [ g.to_sym, skills.count { |s| s[:group] == g } ] }

    def zero_groups = GROUPS.to_h { |g| [ g.to_sym, 0 ] }

    def pending
      skills.select { |s| s[:group] == "pending" }.map { |s| { skill: s[:skill], reason: s[:reason] } }
    end

    def labels
      @labels ||= begin
        mine = (graph_body || { "skills" => [] })["skills"]
        foreign = result[:skills].reject { |r| r[:subject] == @subject.key }.filter_map do |r|
          other = Subject.find_by(key: r[:subject])
          rev = other && SkillGraphRevision.where(subject: other).order(:seq).last
          rev && JSON.parse(rev.body_json)["skills"]
        end.flatten
        (foreign + mine).to_h { |s| [ s["key"], s["label_it"] ] }
      end
    end

    # The programme lines a skill cites: lines of the previous year's programme (the
    # coverage source) and of the second year, each with the line's own text.
    def lines_of(key)
      skill = (graph_body || { "skills" => [] })["skills"].find { |s| s["key"] == key } or return { prima: [], seconda: [] }
      prima_key = Validation::Rules.get(:coverage, :prima_source)
      refs = Array(skill["refs"]).map { |r| { source: r["source"], line: r["line"], role: r["role"] } }
      texts = line_texts(refs)
      rows = refs.map { |r| r.merge(text: texts[[ r[:source], r[:line] ]]) }
      { prima: rows.select { |r| r[:source] == prima_key }, seconda: rows.reject { |r| r[:source] == prima_key } }
    end

    def line_texts(refs)
      SyllabusLine.joins(:syllabus_source).where(syllabus_sources: { key: refs.map { |r| r[:source] }.uniq }, number: refs.map { |r| r[:line] }.uniq)
                  .pluck("syllabus_sources.key", :number, :text).to_h { |source, number, text| [ [ source, number ], text.to_s.strip.first(240) ] }
    end

    # ---- attempts

    def attempts
      @attempts ||= Attempt.where(served_event_id: @run.events.select(:id), context: "diagnosis").includes(:gradings, item_instance: :item_revision).order(:id).to_a
    end

    def skill_of(attempt)
      body = JSON.parse(attempt.item_instance.item_revision.body_json)
      body["kind"] == "testlet" ? Array(body["sub_items"]).first&.fetch("skill", nil) : body["skill"]
    end

    # {[skill, code] => [attempt, ...]} from each attempt's latest grading and from the
    # codes the teacher gave when resolving an attempt.
    def errors_observed
      resolved = Decision.where(kind: "resolve_attempt", student_id: @student.id).order(:id).to_h { |d| (p = JSON.parse(d.payload_json)); [ p["attempt_id"].to_i, p ] }
      found = Hash.new { |h, k| h[k] = [] }
      attempts.each do |attempt|
        decision = resolved[attempt.id]
        if decision
          found[[ skill_of(attempt), decision["error_code"] ]] << attempt if decision["verdict"] == "typical_error" && decision["error_code"]
          next
        end
        grading = attempt.gradings.max_by(&:seq)
        next unless grading&.verdict == "typical_error"

        Array(JSON.parse(grading.error_codes_json || "[]")).first(1).each { |code| found[[ skill_of(attempt), code ]] << attempt }
      end
      found.map do |(skill, code), list|
        row = { skill: skill, code: code, count: list.size, example_attempts: list.first(EXAMPLES).map(&:id) }
        row[:examples] = list.first(EXAMPLES).map { |a| Diagnosis::AnswerText.call(a, served_of(a)) } if @with_answers
        row
      end.sort_by { |r| [ -r[:count], r[:skill].to_s, r[:code].to_s ] }
    end

    def served_of(attempt)
      ItemServed.includes(item_instance: :item_revision).find_by!(diagnosis_event_id: attempt.served_event_id)
    end

    # ---- signals

    def signals
      signals_for(@run, attempts, attempts.size)
    end

    def signals_for(run, attempts, total)
      return { sitting_condition: SITTING_CONDITION, flags: [] } unless run

      dont_know = attempts.count { |a| a.raw == Grading::DONT_KNOW_RAW }
      state = conductor.state
      rapid = state.serves.count do |serve|
        next false unless serve.answered_at

        serve.instance.expected_seconds.to_f.positive? && state.serve_counted_seconds(serve) < RAPID_FACTOR * serve.instance.expected_seconds
      end
      answered = state.serves.count(&:answered_at)
      rapid_share = answered.zero? ? 0.0 : (rapid.to_f / answered).round(2)
      dont_know_share = total.zero? ? 0.0 : (dont_know.to_f / total).round(2)
      flags = []
      flags << "rapid_share" if rapid_share > RAPID_FLAG_SHARE
      flags << "dont_know_share" if dont_know_share > DONT_KNOW_FLAG_SHARE
      { sitting_condition: SITTING_CONDITION, rapid_share: rapid_share, dont_know_share: dont_know_share, dont_know_count: dont_know,
        answers: total, pending_answers: skills.count { |s| s[:state] == "pending" }, flags: flags }
    end
  end
end
