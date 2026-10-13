# frozen_string_literal: true

module Lessons
  module Diagrams
    # strand (WAVE2 2.8, biology.md 2.2; T7): a nucleotide (phosphate, sugar, base), a single strand or a double strand drawn as a ladder. `bottom` must be the
    # complement of `top` (no false pair can be drawn); an RNA double strand is refused until transcription needs it. The bottom bases that a state hides are not
    # in the served data: a position hidden in every state is served with a placeholder letter (the one of the top strand, never the complement), so the page
    # cannot show or compute what the check asks (L2). The pairs are colour-coded by pair (A, T and U one, C and G the other), shaped by pair (angular and
    # rounded) and drawn with two or three rungs; the shapes are a memory aid, the real bases are molecules.
    # The browser twin is app/javascript/lesson/diagrams/science/strand.js; both run test/fixtures/diagrams/types/strand.json.
    module Strand
      extend Contract

      COMPLEMENT = { "A" => "T", "T" => "A", "C" => "G", "G" => "C" }.freeze
      NAMES = { "A" => "adenina", "C" => "citosina", "G" => "guanina", "T" => "timina", "U" => "uracile" }.freeze
      PARTS = { "phosphate" => "fosfato", "sugar" => "zucchero", "base" => "base azotata" }.freeze
      NEUTRAL_DROPS = %w[labels highlight unzip op_it].freeze
      PAIR_NOTE = "Le forme aiutano a ricordare: le vere basi sono molecole."

      class << self
        def static(data, c)
          top = data["top"]
          rna = data["kind"] == "rna"
          bad = top.chars.index { |ch| rna ? ch == "T" : ch == "U" }
          return c.diagram("/top", "#{rna ? 'RNA has U, not T' : 'DNA has T, not U'}: position #{bad + 1} of top", rule: "top-letters") if bad

          case data["mode"]
          when "nucleotide"
            c.diagram("/top", "a nucleotide has one base: top has #{top.size}", rule: "nucleotide-top") if top.size != 1
            c.diagram("/bottom", "a nucleotide has no bottom strand", rule: "nucleotide-bottom") if data.key?("bottom")
          when "single"
            c.diagram("/bottom", "a single strand has no bottom strand", rule: "single-bottom") if data.key?("bottom")
          when "double"
            return c.diagram("/kind", "an RNA double strand is not drawn yet: it waits for transcription", rule: "double-rna") if rna
            return c.diagram("/bottom", "a double strand needs bottom", rule: "double-bottom") unless data["bottom"]
            return c.diagram("/bottom", "bottom has #{data['bottom'].size} bases, top #{top.size}", rule: "bottom-length") if data["bottom"].size != top.size

            wrong = top.chars.each_index.find { |i| COMPLEMENT[top[i]] != data["bottom"][i] }
            c.diagram("/bottom", "position #{wrong + 1} of bottom is not the complement of #{top[wrong]}: A pairs with T, C with G", rule: "bottom-complement") if wrong
          end
        end

        def state(eff, c, path)
          (eff["hide_bottom"] || []).each_with_index do |pos, i|
            if eff["mode"] != "double"
              c.diagram("#{path}/hide_bottom", "hide_bottom is for a double strand", rule: "hide-mode#{path}")
              break
            end
            c.diagram("#{path}/hide_bottom/#{i}", "position #{pos} is past the last base (#{eff['top'].size})", rule: "hide-range#{path}/#{i}") if pos > eff["top"].size
          end
          c.diagram("#{path}/unzip", "unzip is for a double strand", rule: "unzip-mode#{path}") if eff["unzip"] && eff["mode"] != "double"
          letters = eff["kind"] == "rna" ? %w[A C G U] : %w[A C G T]
          (eff["highlight"] || []).each_with_index do |ch, i|
            c.diagram("#{path}/highlight/#{i}", "#{ch} is not a base of #{eff['kind'].upcase} (#{letters.join(', ')})", rule: "highlight#{path}/#{i}") unless letters.include?(ch)
          end
        end

        # The positions (1-based) hidden in every state: their bottom letters never reach the page.
        def always_hidden(data)
          states = Diagrams.effective_states(data)
          states = [ data ] if states.empty?
          states.map { |eff| eff["hide_bottom"] || [] }.reduce { |a, b| a & b } || []
        end

        # The figure as the student's page gets it: bottom with the always-hidden positions replaced by the top's letter (never the complement).
        def served(data, mode: :student)
          out = Lessons::StudentBody.diagram_generic(data)
          if out["bottom"]
            hidden = always_hidden(data)
            out["bottom"] = out["bottom"].chars.each_with_index.map { |ch, i| hidden.include?(i + 1) ? data["top"][i] : ch }.join
          end
          return out unless mode == :select

          out = out.except(*NEUTRAL_DROPS)
          out["states"] = out["states"].map { |s| s.except(*NEUTRAL_DROPS) } if out["states"]
          out
        end

        # Ids in reading order. bases: "top1".. then "bot1" (a nucleotide: "top1"); backbone: "top", "bot" (a nucleotide: "phosphate", "sugar"); rungs: "r1"...
        def targets(data, set)
          n = data["top"].size
          case set.to_s
          when "bases" then (1..n).map { |i| "top#{i}" } + (data["mode"] == "double" ? (1..n).map { |i| "bot#{i}" } : [])
          when "backbone"
            data["mode"] == "nucleotide" ? %w[phosphate sugar] : (data["mode"] == "double" ? %w[top bot] : %w[top])
          when "rungs" then data["mode"] == "double" ? (1..n).map { |i| "r#{i}" } : []
          else []
          end
        end

        def target_names(data, set)
          n = data["top"].size
          case set.to_s
          when "bases"
            hidden = always_hidden(data)
            top = (1..n).to_h { |i| [ "top#{i}", "base #{data['top'][i - 1]} in posizione #{i} (sopra)" ] }
            bot = data["mode"] == "double" ? (1..n).to_h { |i| [ "bot#{i}", hidden.include?(i) ? "base nascosta in posizione #{i} (sotto)" : "base #{data['bottom'][i - 1]} in posizione #{i} (sotto)" ] } : {}
            top.merge(bot)
          when "backbone" then { "phosphate" => "fosfato", "sugar" => "zucchero", "top" => "dorsale di sopra", "bot" => "dorsale di sotto" }
          when "rungs" then (1..n).to_h { |i| [ "r#{i}", "piolo #{i}" ] }
          else {}
          end
        end

        # Every string the state prints (L4): the visible letters, the words of the parts and the pairs, the names of the bases and the count line.
        def printed(data, state = 0)
          eff = Diagrams.effective_states(data)[state] || data
          labels = eff["labels"] || (eff["mode"] == "nucleotide" ? "parts" : "none")
          hidden = eff["hide_bottom"] || []
          out = eff["top"].chars.dup
          out.concat(eff["bottom"].chars.each_with_index.reject { |_, i| hidden.include?(i + 1) }.map(&:first)) if eff["mode"] == "double"
          visible = out.dup
          out.concat(PARTS.values) if labels == "parts"
          out.concat(visible.uniq.map { |ch| NAMES[ch] }) if labels == "bases"
          if eff["mode"] == "double" && labels != "none"
            out << "coppia A-T" << "coppia C-G" << PAIR_NOTE
          end
          (eff["highlight"] || []).each { |ch| out << "#{ch} #{visible.count(ch)}" }
          op = data["states"] && data["states"][state] && data["states"][state]["op_it"]
          out << op if op
          out.uniq
        end
      end
    end
  end
end
