# frozen_string_literal: true

module Lessons
  module Diagrams
    # A sentence analysed in parts: each part an exact substring of the text, in order, not overlapping, except
    # implied parts ("(noi)"). Across states a part with the same id keeps its role (it moves, it does not change).
    module Sentence
      module_function

      def state(eff, c, path)
        text = eff["text_it"]
        parts = eff["parts"]
        if text.nil? || parts.nil?
          c.diagram(path.empty? ? "/text_it" : path, "a sentence needs text_it and parts (at the top level or in the state)", rule: "missing#{path}")
          return
        end
        ids = {}
        cursor = 0
        spans = []
        parts.each_with_index do |p, i|
          at = "#{path}/parts/#{i}"
          c.role("#{at}/role", p["role"])
          c.label("#{at}/label_it", p["label_it"])
          if p["id"]
            c.diagram("#{at}/id", "the part id #{p['id']} is used twice", rule: "part-id#{at}") if ids.key?(p["id"])
            ids[p["id"]] = true
          end
          next if p["implied"]

          found = text.index(p["text_it"], cursor)
          if found
            spans << [ found, found + p["text_it"].size ]
            cursor = found + p["text_it"].size
            next
          end
          anywhere = text.index(p["text_it"])
          if anywhere.nil?
            c.diagram("#{at}/text_it", "parts are exact substrings of text_it: #{p['text_it'].inspect} is not in #{text.inspect}", rule: "substring#{at}")
          elsif spans.any? { |s, e| anywhere < e && anywhere + p["text_it"].size > s }
            c.diagram(at, "the part #{p['text_it'].inspect} overlaps the one before it", rule: "overlap#{at}")
          else
            c.diagram(path.empty? ? "/parts" : "#{path}/parts", "the parts must follow the order of the sentence: #{p['text_it'].inspect} comes earlier in the text", rule: "order#{path}")
          end
        end
        eff["links"].to_a.each_with_index do |l, i|
          at = "#{path}/links/#{i}"
          c.diagram("#{at}/from", "the link starts from a part id that does not exist", rule: "link-from#{at}") unless ids.key?(l["from"])
          c.diagram("#{at}/to", "the link goes to a part id that does not exist", rule: "link-to#{at}") unless ids.key?(l["to"])
          c.label("#{at}/label_it", l["label_it"])
        end
      end

      def across(_data, states, c)
        roles = {}
        states.each_with_index do |eff, i|
          eff["parts"].to_a.each_with_index do |p, j|
            next unless p["id"]

            if roles.key?(p["id"]) && roles[p["id"]] != p["role"]
              c.diagram("/states/#{i}/parts/#{j}/role", "across states a part with the same id keeps its role: #{p['id']} was #{roles[p['id']]}", rule: "role-change-#{i}-#{j}")
            end
            roles[p["id"]] ||= p["role"]
          end
        end
      end
    end
  end
end
