module Teacher
  # The course map of a subject as the teacher reads and releases it (A10): the latest map and the released
  # one, the topics in the recommended order with their stage, the new skills with the programme text beside
  # their refs, the warnings and the release state. Read-only; the release itself is a decision.
  class CourseReview
    SkillRow = Data.define(:key, :label_it, :layer, :refs, :errors)
    Ref = Data.define(:source, :line, :fragment, :role, :text)
    TopicRow = Data.define(:entry, :stage, :latest, :approved_revision_id, :reasons)
    # One step of the path: the plain badge, what is missing in one line, the counts and the students' progress.
    Step = Data.define(:number, :row, :badge, :missing_it, :exercises, :open_findings, :progress) do
      def entry = row.entry
      def lesson? = !row.latest.nil?
      def ready? = %w[ready newer].include?(badge)
    end
    Progress = Data.define(:student, :tries, :done, :total)

    # The words of the mechanical reasons of Course::TopicStage, as one short Italian line each.
    STAGE_LINES = [
      [ /skills of the topic differ/, "Le abilità non corrispondono alla mappa." ],
      [ /pinned lesson revision is not the newest/, "Serve una versione nuova dell'argomento." ],
      [ /not the newest passed revision/, "Serve una versione nuova dell'argomento." ],
      [ /no review by an independent session/, "Manca la revisione della lezione." ],
      [ /sent the lesson revision back/, "Hai rimandato la lezione." ],
      [ /have not passed validation/, "Alcuni esercizi non hanno passato il controllo." ],
      [ /lack an expert review or a blind solve/, "Mancano la revisione o la prova alla cieca di alcuni esercizi." ],
      [ /sent \d+ pinned item/, "Hai rimandato alcuni esercizi." ]
    ].freeze

    attr_reader :subject

    def initialize(subject)
      @subject = subject
    end

    def present? = !latest.nil?
    def latest = @latest ||= Course::State.latest(subject)
    def body = @body ||= latest.body
    def notes = Array(body["notes_it"])
    def warnings = @warnings ||= Course::State.warnings(latest)
    def released_id = @released_id ||= Course::State.released_revision_id(subject)
    def released = released_id && CourseRevision.find_by(id: released_id)
    def open? = !released_id.nil?
    def released_latest? = released_id == latest&.id

    # The topics in map order, each with the stage `banco status` uses (missing reads "da scrivere").
    def topics
      @topics ||= begin
        rows = Course::TopicStage.rows(subject) || {}
        rows.values.map do |row|
          TopicRow.new(row.topic, row.stage, row.latest, row.approved_revision_id, row.gate_reasons)
        end
      end
    end

    # The path: the topics in map order as numbered steps (D-240).
    def steps
      @steps ||= begin
        ids = topics.filter_map { |r| r.latest && Approval::TopicGate.item_revision_ids(r.latest) }.flatten
        open_ids = ReviewFinding.must_be_disposed.where(item_revision_id: ids).pluck(:id, :item_revision_id)
        disposed = ReviewFinding.dispositions
        open_by_item = open_ids.reject { |id, _| disposed.key?(id) }.map(&:last).tally
        topics.each_with_index.map do |row, i|
          item_ids = row.latest ? Approval::TopicGate.item_revision_ids(row.latest) : []
          Step.new(i + 1, row, badge_of(row), missing_line(row), item_ids.size, item_ids.sum { |id| open_by_item[id].to_i }, progress_of(row))
        end
      end
    end

    def ready_count = steps.count(&:ready?)

    def badge_of(row)
      case row.stage
      when "missing" then "missing"
      when "in_review" then "working"
      when "awaiting_teacher" then "ready"
      when "approved" then open? ? "open" : "approved"
      else "newer"
      end
    end

    def missing_line(row)
      case row.stage
      when "missing" then "L'agente non ha ancora scritto la lezione."
      when "in_review" then row.reasons.filter_map { |r| STAGE_LINES.find { |re, _| re.match?(r) }&.last }.uniq.first(2).join(" ").presence || "Gli agenti stanno finendo i controlli."
      when "awaiting_teacher" then "Manca solo la tua revisione."
      when "approved_newer_pending" then "L'agente ha mandato una versione nuova."
      end
    end

    # The official student's progress when the course is released, else the trial students'. Never mixed.
    def students
      @students ||= open? ? [ Student.official ].compact : Student.where(kind: "student").where.not(key: Student::OFFICIAL_KEY).order(:key).to_a
    end

    def progress_of(row)
      return [] unless row.latest

      skills = row.entry["skills"]
      students.map do |student|
        pp = progress_for(student)
        states = skills.map { |k| pp.states[k]&.state.to_s }
        tries = pp.input.tries.count { |t| skills.include?(t.skill) }
        Progress.new(student, tries, states.count { |st| %w[demonstrated consolidated].include?(st) }, skills.size)
      end
    end

    def progress_for(student) = (@progress ||= {})[student.id] ||= Teacher::PracticeProgress.new(subject, student)

    def counts
      tally = topics.map(&:stage).tally
      { in_map: topics.size, approved: tally["approved"].to_i + tally["approved_newer_pending"].to_i, awaiting: tally["awaiting_teacher"].to_i,
        missing: tally["missing"].to_i }
    end

    # The new seconda skills of the map, each ref with the imported programme line beside it.
    def skills
      @skills ||= Array(body["skills"]).map do |s|
        SkillRow.new(s["key"], s["label_it"], s["layer"], Array(s["refs"]).map { |r| ref(r) }, Array(s["errors"]))
      end
    end

    # What opening the course needs (plain reasons for Teacher::Wording); empty when the teacher may open it.
    def release_reasons = @release_reasons ||= Course::Decisions.release_reasons(subject, latest)

    def releasable? = release_reasons.empty?

    # What opening the course needs, each with whether it is done (the two conditions of Course::Decisions.release_reasons).
    def release_checks
      [ [ :graph, release_reasons.none? { |r| r.include?("not validated against the approved graph") } ],
        [ :topic, release_reasons.none? { |r| r.include?("no topic of the course map is approved") } ] ]
    end

    # Reasons that are none of the two checks (the course is already open with this map, no map).
    def other_release_reasons = release_reasons.reject { |r| r.include?("not validated against the approved graph") || r.include?("no topic of the course map is approved") }

    private

    def ref(r)
      source = SyllabusSource.find_by(key: r["source"])
      line = source && SyllabusLine.find_by(syllabus_source: source, number: r["line"])
      Ref.new(r["source"], r["line"], r["fragment"], r["role"], line&.text)
    end
  end
end
