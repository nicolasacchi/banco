# frozen_string_literal: true

module Lessons
  module Diagrams
    # A sentence analysed in parts: each part an exact substring of the text, in order, not overlapping, except
    # implied parts ("(noi)"). Across states a part with the same id keeps its role (it moves, it does not change).
    #
    # Neutral (WAVE2 2.6): the text of the sentence and of each part is text_it, text_en or text_es, exactly one of them, and the
    # parts are written in the language of their sentence. The JS twin is lesson/diagrams/sentence.js.
    module Sentence
      TEXT_KEYS = %w[text_it text_en text_es].freeze

      module_function

      # The one text key a sentence, a state or a part is written in; nil when it has none.
      def key_of(hash) = TEXT_KEYS.find { |k| hash[k] }

      def state(eff, c, path)
        key = key_of(eff)
        text = key && eff[key]
        parts = eff["parts"]
        c.diagram(path.empty? ? "/#{key}" : path, "the sentence is written in one language: #{TEXT_KEYS.select { |k| eff[k] }.join(', ')} are alternatives", rule: "one-language#{path}") if key && TEXT_KEYS.count { |k| eff[k] } > 1
        if text.nil? || parts.nil?
          c.diagram(path.empty? ? "/text_it" : path, "a sentence needs text_it, text_en or text_es and parts (at the top level or in the state)", rule: "missing#{path}")
          return
        end
        ids = {}
        cursor = 0
        spans = []
        parts.each_with_index do |p, i|
          at = "#{path}/parts/#{i}"
          pkey = key_of(p)
          c.diagram("#{at}/#{pkey}", "a part is written in the language of its sentence (#{key}), not #{pkey}", rule: "part-language#{at}") if pkey && pkey != key
          c.diagram(at, "a part is written in the language of its sentence: #{TEXT_KEYS.select { |k| p[k] }.join(', ')} are alternatives", rule: "part-one-language#{at}") if TEXT_KEYS.count { |k| p[k] } > 1
          c.role("#{at}/role", p["role"])
          c.label("#{at}/label_it", p["label_it"])
          if p["id"]
            c.diagram("#{at}/id", "the part id #{p['id']} is used twice", rule: "part-id#{at}") if ids.key?(p["id"])
            ids[p["id"]] = true
          end
          next if p["implied"]

          piece = p[pkey || key]
          next if piece.nil?

          found = text.index(piece, cursor)
          if found
            spans << [ found, found + piece.size ]
            cursor = found + piece.size
            next
          end
          anywhere = text.index(piece)
          if anywhere.nil?
            c.diagram("#{at}/#{pkey || key}", "parts are exact substrings of #{key}: #{piece.inspect} is not in #{text.inspect}", rule: "substring#{at}")
          elsif spans.any? { |s, e| anywhere < e && anywhere + piece.size > s }
            c.diagram(at, "the part #{piece.inspect} overlaps the one before it", rule: "overlap#{at}")
          else
            c.diagram(path.empty? ? "/parts" : "#{path}/parts", "the parts must follow the order of the sentence: #{piece.inspect} comes earlier in the text", rule: "order#{path}")
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
