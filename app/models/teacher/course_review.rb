module Teacher
  # The course map of a subject as the teacher reads and releases it (A10): the latest map and the released
  # one, the topics in the recommended order with their stage, the new skills with the programme text beside
  # their refs, the warnings and the release state. Read-only; the release itself is a decision.
  class CourseReview
    SkillRow = Data.define(:key, :label_it, :layer, :refs, :errors)
    Ref = Data.define(:source, :line, :fragment, :role, :text)
    TopicRow = Data.define(:entry, :stage, :latest, :approved_revision_id, :reasons)

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

    private

    def ref(r)
      source = SyllabusSource.find_by(key: r["source"])
      line = source && SyllabusLine.find_by(syllabus_source: source, number: r["line"])
      Ref.new(r["source"], r["line"], r["fragment"], r["role"], line&.text)
    end
  end
end
