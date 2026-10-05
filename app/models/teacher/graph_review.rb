module Teacher
  # The skill graph of a subject as the teacher approves it (C-04): each skill with its
  # scope, its prerequisite edges, the programme lines it cites (the text of the imported
  # lines), the errors it lists, the flags of config/banco/review_flags.yml, and a diff
  # against the revision approved before. Read-only.
  class GraphReview
    SCOPE_MARK = { "studied" => "★", "integration_studied" => "★", "in_progress" => "☆", "middle_school" => "", "not_in_prima" => "" }.freeze
    Skill = Data.define(:key, :label_it, :layer, :scope, :scope_reason_it, :prerequisites, :composite_of, :deferred, :errors, :refs, :inferred, :flags, :change, :changes)
    Ref = Data.define(:source, :line, :role, :fragment, :text, :section, :other_subject)

    attr_reader :subject, :revision, :approved

    def initialize(subject)
      @subject = subject
      @revision = SkillGraphRevision.where(subject: subject).order(:seq).last
      @approved = SubjectStage.approved_graph(subject)
    end

    def present? = !@revision.nil?
    def body = @body ||= JSON.parse(revision.body_json)
    def previous = @previous ||= approved && approved.id != revision.id ? JSON.parse(approved.body_json) : nil
    def approved_latest? = !approved.nil? && approved.id == revision&.id

    def skills
      @skills ||= body["skills"].map do |s|
        refs = Array(s["refs"]).map { |r| Ref.new(r["source"], r["line"], r["role"], r["fragment"], line_text(r["source"], r["line"]), section_of(r["source"], r["line"]), other_subject?(r["source"], r["line"])) }
        change, changes = changes_of(s)
        Skill.new(s["key"], s["label_it"], s["layer"], s["scope"], s["scope_reason_it"], Array(s["prerequisites"]), Array(s["composite_of"]),
                  deferred_of(s),
                  Array(s["errors"]), refs, refs.none? { |r| r.role == "taught_in" }, flags_of(s, refs), change, changes)
      end
    end

    def removed
      return [] unless previous

      (previous["skills"].map { |s| s["key"] } - body["skills"].map { |s| s["key"] }).map { |k| previous["skills"].find { |s| s["key"] == k } }
    end

    # The author's notes for the teacher (programme flags, D-096), shown above the skills.
    def notes = Array(body["notes_it"])

    def excluded
      @excluded ||= Array(body["excluded"]).map { |e| { line: e["line"], fragment: e["fragment"], reason_it: e["reason_it"], text: line_text(prima_source, e["line"]) } }
    end

    def inferred_share
      skills.empty? ? 0 : (100.0 * skills.count(&:inferred) / skills.size).round
    end

    def first_revision? = approved.nil?

    def changed? = skills.any? { |s| s.change != :same } || removed.any?

    # Whether the teacher can approve it now, and why not.
    def approval
      reasons = []
      reasons << "already_approved" if approved_latest?
      { allowed: reasons.empty?, reasons: reasons }
    end

    def self.scope_label(scope) = I18n.t("teacher.graph.scope.#{scope}")

    private

    def prima_source = @prima_source ||= Validation::Rules.get(:coverage, :prima_source)

    # The "## " heading of a cited line, and whether it is not the section most of the
    # graph's citations of that source sit in (another subject's line; no majority: no).
    def section_of(source, number)
      @sections ||= {}
      @sections[source] ||= begin
        src = SyllabusSource.find_by(key: source)
        src ? Syllabus::Sections.call(SyllabusLine.where(syllabus_source: src).order(:number).to_a) : {}
      end
      @sections[source][number]
    end

    def own_section(source)
      @own_sections ||= {}
      @own_sections.fetch(source) do
        counts = body["skills"].flat_map { |s| Array(s["refs"]) }.select { |r| r["source"] == source }
                               .filter_map { |r| section_of(source, r["line"]) }.tally.sort_by { |_, n| -n }
        @own_sections[source] = counts.size >= 2 && counts[0][1] == counts[1][1] ? nil : counts.dig(0, 0)
      end
    end

    def other_subject?(source, number)
      own = own_section(source)
      !own.nil? && (section = section_of(source, number)) && section != own ? true : false
    end

    def line_text(source, number)
      @texts ||= SyllabusLine.joins(:syllabus_source).pluck("syllabus_sources.key", :number, :text).to_h { |k, n, t| [ [ k, n ], t.to_s.strip ] }
      @texts[[ source, number ]]
    end

    def changes_of(skill)
      return [ :same, [] ] unless previous

      old = previous["skills"].find { |s| s["key"] == skill["key"] }
      return [ :added, [] ] unless old

      diff = %w[label_it layer scope scope_reason_it].reject { |f| old[f] == skill[f] }
      diff << "prerequisites" if Array(old["prerequisites"]).sort != Array(skill["prerequisites"]).sort
      diff << "deferred" if deferred_of(old).map { |d| d.slice(:skill, :where) } .sort_by(&:to_s) != deferred_of(skill).map { |d| d.slice(:skill, :where) }.sort_by(&:to_s)
      diff << "composite_of" if Array(old["composite_of"]).sort != Array(skill["composite_of"]).sort
      diff << "refs" if refs_set(old) != refs_set(skill)
      diff << "errors" if Array(old["errors"]).map { |e| e["code"] }.sort != Array(skill["errors"]).map { |e| e["code"] }.sort
      [ diff.empty? ? :same : :changed, diff ]
    end

    # D-091: declared cross-subject edges whose graph is not approved yet: [{skill:, reason_it:, where:}].
    def deferred_of(skill)
      own = Array(skill["deferred_prerequisites"]).map { |d| { skill: d["skill"], reason_it: d["reason_it"], where: :prerequisite } }
      implied = Array(skill["errors"]).flat_map do |e|
        Array(e["deferred_implicates"]).map { |d| { skill: d["skill"], reason_it: d["reason_it"], where: :implicate, error: e["code"] } }
      end
      own + implied
    end

    def refs_set(skill) = Array(skill["refs"]).map { |r| [ r["source"], r["line"], r["role"] ] }.sort

    def flags_of(skill, refs)
      self.class.flag_rules.filter_map do |rule|
        next if rule["subject"] && rule["subject"] != subject.key

        hit = if rule["lines"]
          refs.any? { |r| r.source == rule["source"] && r.line.between?(*rule["lines"]) }
        elsif rule["not_source"]
          refs.any? { |r| r.source != rule["not_source"] }
        end
        rule["id"] if hit
      end
    end

    class << self
      def flag_rules = @flag_rules ||= YAML.safe_load_file(Rails.root.join("config/banco/review_flags.yml")).fetch("flags")
    end
  end
end
