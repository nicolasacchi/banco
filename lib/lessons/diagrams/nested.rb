# frozen_string_literal: true

module Lessons
  module Diagrams
    # nested (WAVE2 2.1, biology.md 2.5; T4b, D-312): "is made of", drawn as boxes inside boxes. `levels` go from the inside out (3 to 6), each with a name
    # and an optional example; `inside` is a dashed box inside the innermost level (not a level); a state's `focus` lights one level. Select set `levels`:
    # the level ids, outermost first (the reading order of the drawing); the select figure has no names (the examples stay), no focus, no inside.
    # The browser twin is app/javascript/lesson/diagrams/graph/nested.js; both run test/fixtures/diagrams/types/nested.json.
    module Nested
      extend Contract

      NEUTRAL_DROPS = %w[focus inside states].freeze

      class << self
        # The first finding of the whole figure, in the order of the browser's semantic().
        def static(data, c)
          levels = data["levels"]
          levels.each_with_index do |lv, i|
            return c.diagram("/levels/#{i}/id", "the id #{lv['id']} is used twice", rule: "id#{i}") if levels.index { |x| x["id"] == lv["id"] } != i

            before = c.findings.size
            c.label("/levels/#{i}/label_it", lv["label_it"])
            return if c.findings.size > before

            same = levels.index { |x| x["label_it"].strip.downcase == lv["label_it"].strip.downcase }
            return c.diagram("/levels/#{i}/label_it", "two levels are called #{lv['label_it']}", rule: "same#{i}") if same != i
          end
          c.label("/inside/label_it", data.dig("inside", "label_it")) if data["inside"]
          nil
        end

        def state(eff, c, path)
          return if eff["focus"].nil? || eff["levels"].any? { |l| l["id"] == eff["focus"] }

          c.diagram("#{path}/focus", "#{eff['focus']} is not the id of a level", rule: "focus#{path}")
        end

        # The figure as the student's page gets it; a select check's figure has no focus, no inside and no states (its names are not drawn).
        def served(data, mode: :student)
          out = Lessons::StudentBody.diagram_generic(data)
          mode == :select ? out.except(*NEUTRAL_DROPS) : out
        end

        # Ids of set `levels` in reading order: the outermost level first.
        def targets(data, set) = set.to_s == "levels" ? data["levels"].reverse.map { |l| l["id"] } : []

        def target_names(data, set) = set.to_s == "levels" ? data["levels"].to_h { |l| [ l["id"], l["label_it"] ] } : {}

        # Every candidate of the select figure is a header zone drawn alike: what the served figure could still mark (a focus) is dropped (L3).
        def select_signatures(data, set)
          figure = served(data, mode: :select)
          targets(data, set).to_h { |id| [ id, figure["focus"] == id ] }
        end

        # Every string the state prints (L4): the names, the examples, the inside box and the state's line.
        def printed(data, state = 0)
          out = data["levels"].flat_map { |l| [ l["label_it"], l["example_it"] ] }.compact
          out.push(data.dig("inside", "label_it"), data.dig("inside", "note_it")) if data["inside"]
          op = data["states"] && data["states"][state] && data["states"][state]["op_it"]
          out << op if op
          out.compact.uniq
        end

        def reachable(_data) = []
      end
    end
  end
end
