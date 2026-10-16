module Search
  module Builders
    # What the real students typed: the entry test's answers (as Diagnosis::AnswerText reads them), the practice answers and the
    # texts refused as unreadable (D-298). `student_answer` documents are for the teacher's door alone (audience "teacher"):
    # no other door asks for the kind, and no embedding ever sees them.
    module Answers
      module_function

      def call
        diagnosis + practice + refused
      end

      def diagnosis
        Attempt.where(context: "diagnosis").where.not(served_event_id: nil).includes(:student, item_instance: { item_revision: { item: :subject } }).order(:id).filter_map do |attempt|
          next unless attempt.student.kind == "student"

          served = ItemServed.find_by(diagnosis_event_id: attempt.served_event_id) or next
          text = ::Diagnosis::AnswerText.call(attempt, served).to_s
          doc(attempt.student, attempt.item_instance, text, at: attempt.answered_at, anchor: "a#{attempt.id}", status: verdict(attempt))
        end
      end

      def verdict(attempt) = attempt.gradings.to_a.max_by(&:seq)&.verdict

      def practice
        PracticeAttempt.includes(:student, :gradings, practice_serve: { item_instance: { item_revision: { item: :subject } } }).order(:id).filter_map do |attempt|
          next unless attempt.student.kind == "student"

          serve = attempt.practice_serve
          doc(attempt.student, serve.item_instance, practice_text(attempt, serve), at: attempt.answered_at, anchor: "p#{attempt.id}",
                                                                                   status: attempt.latest_grading&.verdict)
        end
      end

      def practice_text(attempt, serve)
        instance = serve.item_instance
        body = JSON.parse(instance.item_revision.body_json)
        display = JSON.parse(instance.display_json)
        map = serve.id_map_json.present? ? JSON.parse(serve.id_map_json) : {}
        texts = %w[options elements left right].flat_map { |k| Array(display[k]) }.to_h { |e| [ e["id"], e["text"] ] }
        ::Diagnosis::AnswerText.words(body["component"], attempt.raw, ->(id) { texts[map.fetch(id.to_s, id.to_s)] || id.to_s }).to_s
      rescue JSON::ParserError, NoMethodError
        attempt.raw.to_s
      end

      # The refused texts: app events carry the text, the id of the served event or of the serve says which item it was.
      def refused
        AppEvent.where(kind: %w[invalid_input practice_invalid_input]).includes(:student).order(:id).filter_map do |event|
          next unless event.student&.kind == "student"

          payload = JSON.parse(event.payload_json.to_s)
          text = payload["text"]
          next unless text.is_a?(String) && text.present?

          instance = if event.kind == "invalid_input"
            ItemServed.includes(item_instance: { item_revision: { item: :subject } }).find_by(diagnosis_event_id: payload["served_event_id"])&.item_instance
          else
            PracticeServe.includes(item_instance: { item_revision: { item: :subject } }).find_by(id: payload["serve_id"])&.item_instance
          end
          instance or next
          doc(event.student, instance, text, at: event.created_at, anchor: "e#{event.id}", status: "refused")
        end
      end

      def doc(student, instance, text, at:, anchor:, status:)
        return nil if text.blank?

        revision = instance.item_revision
        item = revision.item
        body = JSON.parse(revision.body_json)
        stem = Text.plain(body.dig("prompt", "stem_it") || Array(body["sub_items"]).first&.dig("prompt", "stem_it"))
        Doc.build(kind: "student_answer", key: item.key, title: stem.presence || item.key, body: text, subject: item.subject.key, status: status,
                  anchor: anchor, skill: Items.skill_of(body), student_key: student.key, occurred_at: at.utc.iso8601,
                  lang: ::Lessons::Lang.target(item.subject.key) || "it")
      end
    end
  end
end
