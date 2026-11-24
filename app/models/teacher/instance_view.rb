module Teacher
  # One stored instance of an item as the teacher reads it (C-04): the stem, the choices
  # the student would see, the key in words, the typical errors with their ids and values,
  # and the solution steps. Texts are the agent's own, shown escaped; the markup of the
  # student's page is not drawn here ("Prova" plays the item as S). A bilingual item (D-402) is read in both layers, «target — italiano», as the student
  # reads it with the translation open: the teacher's pages stay Italian and show the translation open.
  class InstanceView
    attr_reader :number, :id, :stem, :choices, :key, :errors, :steps, :final, :hints

    # number: 1-based position among the shown samples.
    def initialize(instance, body, number)
      @number = number
      @id = instance.id
      display = JSON.parse(instance.display_json)
      answer = JSON.parse(instance.answer_json)
      kind = body["kind"]
      @stem = [ Items::Text.both_of(body, "passage"), Items::Text.both_of(body["prompt"], "stem"), Items::Text.both_of(display, "stem"),
                Items::Text.both_of(display, "passage") ].compact.uniq.join(" ")
      @stem = Items::Text.both_of(body, "passage").to_s if kind == "testlet"
      @choices = choices_of(display)
      @key = key_in_words(kind, body["component"], display, answer)
      @errors = errors_of(instance, body)
      @hints = hints_of(instance, body)
      solution = instance.solution_json.present? ? JSON.parse(instance.solution_json) : {}
      @steps = Array(solution["steps"]).map { |s| Items::Text.both_of(s, "text") }
      @final = Items::Text.final_both(solution)
    end

    private

    def texts(display)
      %w[options elements left right].flat_map { |k| Array(display[k]) }.to_h { |e| [ e["id"], Items::Text.option_both(e) ] }
    end

    def choices_of(display)
      %w[options elements left right].filter_map do |k|
        next unless display[k]

        [ k, display[k].map { |e| "#{e['id']}: #{Items::Text.option_both(e)}" } ]
      end.to_h
    end

    def key_in_words(kind, component, display, answer)
      return I18n.t("teacher.test.key_rubric") if kind == "short_answer"
      return answer.map { |id, v| "#{id}: #{v.is_a?(Hash) ? v.to_json : v}" }.join("; ") if kind == "testlet" && answer.is_a?(Hash)

      shown = texts(display)
      case component
      when "choice" then shown[answer] ? "#{answer}: #{shown[answer]}" : answer.to_s
      when "ordering" then Array(answer).map { |id| shown[id] || id }.join(" → ")
      when "matching" then answer.to_h.map { |l, r| "#{shown[l] || l} – #{shown[r] || r}" }.join("; ")
      when "fraction" then answer.is_a?(Hash) ? "#{answer['n']}/#{answer['d']}" : answer.to_s
      when "expression" then answer.is_a?(Hash) ? answer["latex"].to_s : answer.to_s
      else answer.to_s
      end
    end

    # The errors an instance declares, each with the item's message for the code (what the student reads
    # when the answer hits it); message is nil when the catalogue has no text for the code.
    def errors_of(instance, body)
      raw = instance.errors_json.present? ? JSON.parse(instance.errors_json) : []
      messages = catalogue(body).to_h { |e| [ e["code"], Items::Text.both_of(e, "message") ] }
      return raw.map { |e| { code: e["code"], value: e["value"].to_s, message: messages[e["code"]] } } if raw.is_a?(Array)

      raw.flat_map { |sub, list| Array(list).map { |e| { code: e["code"], value: "#{sub}: #{e['value']}", message: messages[e["code"]] } } }
    end

    def catalogue(body)
      return Array(body["error_catalogue"]) unless body["kind"] == "testlet"

      Array(body["sub_items"]).flat_map { |s| Array(s["error_catalogue"]) }
    end

    # The effective hints of a practice instance: its own, else the item's (A2.4), each in both layers when the item is bilingual (the stored own hints
    # are a list, or an object {hints_<lang>, hints_it}, as Practice::Instances.hints_source reads them). Empty for a diagnosis item.
    def hints_of(instance, body)
      source = Practice::Instances.hints_source(instance, body)
      target = Items::Text.hints(source)
      italian = Items::Text.lang(source, "hints") ? Array(source["hints_it"]) : []
      target.each_with_index.map { |text, i| Items::Text.both(text, italian[i]) }
    end
  end
end
