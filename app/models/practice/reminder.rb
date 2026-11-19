module Practice
  # The line «Ricorda: …» above an exercise (D-358). When an exercise is served, the student's own recent tries of the skill are read (the
  # loader's tries: the latest grading or the teacher's resolution of each, D-352): the most recent typical error among the last WINDOW tries
  # whose code the served item also declares gives the line. The text is the item's own catalogue message for that code; when the item has
  # none (it declares the code only in its instances' error values), the skill graph's description of the error.
  #
  # It is not a hint: it changes no counter, no try, no state; the engine and the rules version do not know it. It is recorded as the append-only
  # app event `practice_reminder_shown` ({serve_id, code, source}), once per serve and code, so the teacher can tell afterwards that it was on the page
  # (`Practice::AttemptLog` shows it in the detail of a try). A text that states the answer of the served instance is never used: the message of an item
  # is written for after a wrong answer, and this one is read before.
  #
  #   Practice::Reminder.call(serve, student:, description: ->(code) { ... })  # => Line or nil
  module Reminder
    KIND = "practice_reminder_shown".freeze
    WINDOW = 10
    SOURCES = %w[item graph].freeze

    Line = Data.define(:code, :text_it, :source)

    module_function

    # description: a callable, the skill graph's description_it of an error code of the serve's skill (nil when it has none).
    # record: false only reads.
    def call(serve, student:, description:, record: true)
      line = line_for(serve, student, description) or return nil
      write(serve, student, line) if record
      line
    end

    # {code, source, at} of the reminders of a serve, oldest first (what the teacher reads).
    def shown(serve_ids)
      ids = Array(serve_ids)
      return {} if ids.empty?

      AppEvent.where(kind: KIND).where("json_extract(payload_json, '$.serve_id') IN (?)", ids)
              .order(:id).each_with_object(Hash.new { |h, k| h[k] = [] }) do |event, out|
        payload = JSON.parse(event.payload_json.to_s)
        out[payload["serve_id"]] << { code: payload["code"], source: payload["source"], at: event.created_at }
      end
    end

    def line_for(serve, student, description)
      instance = serve.item_instance
      return nil if Instances.body(instance)["kind"] == "testlet"

      declared = declared_codes(instance)
      return nil if declared.empty?

      leaks = needles(instance)
      recent_codes(serve, student).each do |code|
        next unless declared.include?(code)

        line = text_for(instance, code, description, leaks) and return line
      end
      nil
    end

    # The codes of the typical errors among the student's last WINDOW tries of the skill, the most recent first.
    def recent_codes(serve, student)
      subject = Subject.find_by(key: serve.skill_key.split(".").first) or return []
      tries = Loader.for(student, subject: subject, skill: serve.skill_key, seeds: false).tries
      tries.sort_by { |t| [ t.at, t.serve_id, t.try_number ] }.last(WINDOW).reverse
           .filter_map { |t| t.outcome == :typical_error ? t.error_codes.first : nil }
    end

    # What the served item declares among its errors: the codes of its catalogue and of its instance's error values.
    def declared_codes(instance)
      catalogue = Array(Instances.body(instance)["error_catalogue"]).filter_map { |e| e["code"] }
      values = Instances.errors(instance)
      (catalogue + (values.is_a?(Array) ? values.filter_map { |e| e["code"] } : [])).to_set
    end

    def text_for(instance, code, description, leaks)
      item = Instances.message_for(instance, code).to_s.strip
      return Line.new(code: code, text_it: item, source: "item") if item.present? && clean?(item, leaks)

      graph = description.call(code).to_s.strip
      Line.new(code: code, text_it: graph, source: "graph") if graph.present? && clean?(graph, leaks)
    end

    def clean?(text, leaks) = leaks.none? { |needle| Validation::Answers.contains?(text, needle) }

    # The texts that are the answer of this instance: its key and accepted forms (a choice: the text of the right option).
    def needles(instance)
      spec = Grading::Spec.from_instance(instance)
      if spec.component == "choice"
        right = Array(spec.display.is_a?(Hash) ? spec.display["options"] : nil).find { |o| o["id"] == spec.answer.to_s }
        right ? [ right["text"].to_s ] : []
      else
        Validation::Answers.key_texts(spec.component, spec.answer, accept: Array(spec.accept))
      end
    end

    # One row per serve and code, however many times the page is opened on the serve.
    def write(serve, student, line)
      return if shown(serve.id)[serve.id].any? { |r| r[:code] == line.code }

      AppEvent.create!(kind: KIND, student: student, payload_json: { serve_id: serve.id, code: line.code, source: line.source }.to_json)
    end
  end
end
