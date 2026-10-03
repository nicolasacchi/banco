module Diagnosis
  # The student's answer in words, for the end-of-subject screen: shown ids are
  # turned back into the texts the student saw (through the logged id map), so a
  # choice reads "Produrre automobili", not "o2".
  module AnswerText
    module_function

    def call(attempt, served)
      raw = attempt.raw
      return I18n.t("summary.dont_know_answer") if raw == Grading::DONT_KNOW_RAW

      body = JSON.parse(served.item_instance.item_revision.body_json)
      return testlet(raw, body, served) if body["kind"] == "testlet"

      component = body["kind"] == "short_answer" ? "short_answer" : body["component"]
      display = JSON.parse(served.item_instance.display_json)
      map = served.id_map_json.present? ? JSON.parse(served.id_map_json) : {}
      texts = (%w[options elements left right].flat_map { |k| Array(display[k]) }).to_h { |e| [ e["id"], e["text"] ] }
      shown = ->(id) { texts[map.fetch(id.to_s, id.to_s)] || id.to_s }
      words(component, raw, shown)
    rescue JSON::ParserError
      raw.to_s
    end

    # One numbered line per sub item, in the order of the passage's questions.
    def testlet(raw, body, served)
      answers = JSON.parse(raw)
      display = JSON.parse(served.item_instance.display_json)
      maps = served.id_map_json.present? ? JSON.parse(served.id_map_json) : {}
      Array(body["sub_items"]).each_with_index.map do |sub, i|
        shown_display = Array(display["sub_items"]).find { |s| s["id"] == sub["id"] }&.fetch("display", {}) || {}
        map = maps[sub["id"]] || {}
        texts = (%w[options elements left right].flat_map { |k| Array(shown_display[k]) }).to_h { |e| [ e["id"], e["text"] ] }
        sub_raw = answers[sub["id"]].to_s
        text = sub_raw == Grading::DONT_KNOW_RAW ? I18n.t("summary.dont_know_answer") : words(sub["component"], sub_raw, ->(id) { texts[map.fetch(id.to_s, id.to_s)] || id.to_s })
        "#{i + 1}. #{text}"
      end.join("\n")
    end

    def words(component, raw, shown)
      case component
      when "choice" then shown.call(raw)
      when "ordering" then JSON.parse(raw).map { |id| shown.call(id) }.join(" → ")
      when "matching" then JSON.parse(raw).map { |l, r| "#{shown.call(l)} – #{shown.call(r)}" }.join("; ")
      when "fraction" then fraction(JSON.parse(raw))
      when "expression" then "$#{raw}$"
      else raw.to_s
      end
    end

    def fraction(boxes)
      base = "#{boxes['n']}/#{boxes['d']}"
      boxes["w"].to_s.strip.empty? ? base : "#{boxes['w']} #{base}"
    end
  end
end
