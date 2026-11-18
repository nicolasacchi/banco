module Speech
  # Brings the clips up to date for the lessons that matter now (D-359, `bin/rails banco:speech:backfill`): the lesson revisions the official student can
  # see (Course::Catalog) and the approved ones (every topic revision a teacher approved). For each lesson/2 revision:
  #   - a passed render with segments: the clips it needs are counted, and SpeakLessonRevisionJob is enqueued when some are missing;
  #   - no such render (the revision was drawn before the segments were collected, or never): RenderLessonRevisionJob draws it again, and its pass
  #     hands the revision to SpeakLessonRevisionJob;
  #   - a render that failed at this version of the host, or an error row: left alone (the teacher's gate says why).
  # And the samples of «Prova le voci» (Speech::Samples). A dry run (confirm: false) only counts.
  module Backfill
    Row = Data.define(:revision, :action, :missing, :total)

    module_function

    def revisions
      visible = Course::Catalog.for(Student.official).flat_map { |subject| subject.topics.map(&:lesson_revision) }
      approved = Decision.where(kind: "approve_topic").filter_map do |d|
        TopicRevision.find_by(id: JSON.parse(d.payload_json)["topic_revision_id"])&.lesson_revision
      end
      (visible + approved).compact.uniq.select(&:lesson2?).sort_by(&:id)
    end

    def rows
      revisions.map do |revision|
        entries = Plan.entries(revision)
        verdict = LessonRender.verdict_for(revision)
        if Plan.segments(revision)
          missing = entries.count { |e| !Clips.exist?(e.key) }
          Row.new(revision: revision, action: missing.positive? ? :speak : :complete, missing: missing, total: entries.size)
        elsif verdict&.status == "failed" && verdict.harness_version == Validation::Harness.lesson_version
          Row.new(revision: revision, action: :render_failed, missing: 0, total: 0)
        else
          Row.new(revision: revision, action: :render, missing: 0, total: 0)
        end
      end
    end

    # Enqueues the work of +rows+ when +confirm+; always answers the counts: { revisions:, speak:, render:, complete:, render_failed:, missing_clips:, samples_missing: }.
    def run(confirm: false, rows: self.rows)
      samples = Samples.entries
      samples_missing = samples.count { |e| !Clips.exist?(e.key) }
      counts = rows.group_by(&:action).transform_values(&:size)
      summary = { revisions: rows.size, speak: counts.fetch(:speak, 0), render: counts.fetch(:render, 0), complete: counts.fetch(:complete, 0),
                  render_failed: counts.fetch(:render_failed, 0), missing_clips: rows.sum(&:missing), samples_missing: samples_missing }
      if confirm
        rows.each do |row|
          case row.action
          when :speak then SpeakLessonRevisionJob.perform_later(row.revision.id)
          when :render then RenderLessonRevisionJob.perform_later(row.revision.id)
          end
        end
        SpeakSamplesJob.perform_later if samples_missing.positive?
      end
      summary
    end
  end
end
