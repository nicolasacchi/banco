# frozen_string_literal: true

module Lessons
  # banco.diagram/1 (A7, A8) on the Ruby side: the state overlay, the semantic checks the JSON schema cannot make
  # (E-LESSON-DIAGRAM and its kin, with the JSON pointer of the offending member), and the solution fields.
  # The schema column of test/fixtures/diagrams/vectors.json is config/banco/schemas/diagram.json; the semantic
  # column is this module. One module per type in lib/lessons/diagrams/.
  #
  # State rule (A7): a state overlays the top level, shallowly. The effective state i is the top-level object with
  # each key present in states[i] replacing the key of the same name; op_it, groups, next_label_it exist only in
  # states; alt_it, caption_it, size and the solution fields (x_value) are top level only. The merge is done
  # once, here, before the checks and before serving (StudentBody), so the browser receives full states.
  module Diagrams
    # path: JSON pointer relative to the diagram; rule: a short stable name for de-duplication.
    Finding = Data.define(:code, :path, :message, :rule)

    class Collector
      attr_reader :subject, :findings

      def initialize(subject)
        @subject = subject
        @findings = []
      end

      def add(code, path, message, rule: nil)
        @findings << Finding.new(code: code, path: path, message: message, rule: rule || "#{code}#{path}")
        self
      end

      def diagram(path, message, rule: nil) = add("E-LESSON-DIAGRAM", path, message, rule: rule)
      def map(path, message, rule: nil) = add("E-LESSON-MAP", path, message, rule: rule)

      # A role must be one of the subject's palette (common roles included).
      def role(path, name)
        add("E-LESSON-ROLE", path, "#{name} is not a colour role of #{subject}'s palette", rule: "role#{path}") unless Lessons::Palette.role?(subject, name)
      end

      # A label: at most label_words_max words, a $...$ counting as one.
      def label(path, text)
        return if text.nil?

        n = Diagrams.label_words(text)
        max = Validation::Rules.get(:lesson2, :label_words_max)
        diagram(path, "a label has #{n} words (at most #{max})", rule: "label#{path}") if n > max
      end

      def tex(path, text)
        Lessons::Markup.check_tex(text.to_s, 1)
      rescue Lessons::Markup::Refused => e
        diagram(path, e.construct, rule: "tex#{path}")
      end
    end

    # Ruby modules by diagram type. The nine of release 1 check their data; the 26 of wave 2 are contract stubs
    # (Contract) until their track builds them. Types without a schema (calendar, rgb, sheet) have no module yet.
    TYPES = {
      "equation_parts" => "EquationParts", "number_line" => "NumberLine", "balance" => "Balance", "area_model" => "AreaModel",
      "cartesian" => "Cartesian", "sentence" => "Sentence", "concept_map" => "ConceptMap", "flow" => "Flow", "table" => "Table",
      "network" => "Network", "chain" => "Chain", "nested" => "Nested", "timeline" => "Timeline", "map" => "Map", "insolation" => "Insolation",
      "cross_section" => "CrossSection", "climograph" => "Climograph", "bar_model" => "BarModel", "seats" => "Seats", "chart" => "Chart",
      "scale" => "Scale", "periodic_table" => "PeriodicTable", "register" => "Register", "column_calc" => "ColumnCalc", "paradigm" => "Paradigm",
      "word_parts" => "WordParts", "mirror" => "Mirror", "document" => "Document", "formula" => "Formula", "molecule" => "Molecule",
      "strand" => "Strand", "particles" => "Particles", "phase_changes" => "PhaseChanges", "cell" => "Cell", "program" => "Program"
    }.freeze

    module_function

    def schema_def(type) = (@defs ||= JSON.parse(File.read(File.join(Banco::Schemas.root, "config/banco/schemas/diagram.json"))).fetch("$defs")).fetch(type)

    def state_keys(type) = schema_def(type)["x-banco-state-keys"].to_a + schema_def(type)["x-banco-state-only-keys"].to_a

    # Names of the solution fields of a type (x-banco-solution in diagram.json): never served as such.
    def solution_fields(type)
      props = schema_def(type).fetch("properties")
      props.select { |_k, v| v.is_a?(Hash) && v["x-banco-solution"] }.keys
    end

    # The effective states: [] without states, else one full hash per state (no "states" member).
    def effective_states(data)
      states = data["states"]
      return [] unless states.is_a?(Array)

      base = data.reject { |k, _| k == "states" }
      states.map { |s| s.is_a?(Hash) ? base.merge(s) : base }
    end

    # The diagram with its states replaced by the effective ones.
    def merge_states(data)
      eff = effective_states(data)
      eff.empty? ? data : data.merge("states" => eff)
    end

    # The module of a diagram type, or nil.
    def module_for(type) = TYPES.key?(type) ? const_get(TYPES.fetch(type)) : nil

    # The served form a type's module builds itself (a station resolved, a hidden value cut out, a computed value added), or nil when the
    # type is served as the generic projection says (StudentBody.diagram_generic). A stub raises NotImplementedError: nil too.
    def served(data, mode: :student)
      mod = module_for(data["type"])
      mod.respond_to?(:served) ? mod.served(data, mode: mode) : nil
    rescue NotImplementedError
      nil
    end

    # The numbers a check accepts as its answer (and its accepted variants), as exact numbers: what L4 and L5 compare with a figure's numbers.
    def answer_numbers(check)
      texts = case check["component"]
      when "number", "fraction" then [ check["answer"] ]
      when "normalized_text" then [ check["answer"], *Array(check["accept"]) ]
      when "choice" then [ Array(check["options"]).find { |o| o["id"] == check["answer"] }&.fetch("text_it", nil) ]
      else []
      end
      texts.compact.filter_map { |t| num(t.to_s.delete("$ ").tr("\u2212", "-").presence || "x") }
    end

    # Findings of L4/L5 for one figure against the checks of its card: [{ code:, check_path:, message: }].
    def answer_leaks(figure, checks)
      mod = module_for(figure["type"]) or return []
      return [] unless mod.respond_to?(:reachable) && Types.available?(:diagram, figure["type"])

      out = []
      reach = mod.reachable(figure)
      checks.each do |cpath, check, cline|
        mine = answer_numbers(check)
        next if mine.empty?

        shown = Array(effective_states(figure).then { |s| s.empty? ? [ figure ] : s }).each_index.flat_map { |i| mod.printed(figure, i) }.filter_map { |t| num(t) }
        if (hit = mine.find { |a| shown.include?(a) })
          out << { code: "W-CHECK-ANSWER-IN-DIAGRAM", check_path: "#{cpath}/answer", check_line: cline, message: "the answer #{Lessons::Num.to_s(hit)} is a number the figure of this card prints (in some state): a student can copy it instead of finding it" }
        end
        next if reach == :over_cap || reach.empty? || check["reachable_ok_it"]

        reached = reach.filter_map { |t| num(t) }
        if (hit = mine.find { |a| reached.include?(a) })
          out << { code: "E-CHECK-ANSWER-BY-SIMULATION", check_path: "#{cpath}/answer", check_line: cline, message: "the answer #{Lessons::Num.to_s(hit)} is a number the figure can show when its controls move inside their ranges: ask another number, or say in reachable_ok_it why the reach does not give it away" }
        end
      end
      out << { code: "E-DIAGRAM-REACHABLE-CAP", check_path: nil, message: "the figure can show more than #{Contract::REACHABLE_CAP} numbers inside its ranges, and the card has a check: narrow the ranges or move the check" } if reach == :over_cap && checks.any?
      out
    rescue NotImplementedError
      []
    end

    def label_words(text) = text.to_s.gsub(/\$[^$]*\$/, "M").split.size

    # Findings [Finding] of a diagram (type known to the schema) for a lesson of +subject+.
    def check(data, subject:)
      c = Collector.new(subject)
      type = data["type"]
      mod = TYPES.key?(type) ? const_get(TYPES.fetch(type)) : nil
      return [ Finding.new(code: "E-LESSON-DIAGRAM", path: "/type", message: "unknown diagram type #{type.inspect}", rule: "type") ] unless mod

      alt = data["alt_it"].to_s.split.size
      lo, hi = Validation::Rules.get(:lesson2, :alt_words)
      c.add("E-LESSON-ALT", "/alt_it", "alt_it has #{alt} words (#{lo} to #{hi})", rule: "alt") unless (lo..hi).cover?(alt)
      mod.static(data, c) if mod.respond_to?(:static)
      states = effective_states(data)
      if states.empty?
        mod.state(data, c, "")
      else
        states.each_with_index { |eff, i| mod.state(eff, c, "/states/#{i}") }
        mod.across(data, states, c) if mod.respond_to?(:across)
      end
      c.findings
    rescue StandardError => e
      raise if e.is_a?(NoMemoryError)

      c.findings + [ Finding.new(code: "E-LESSON-DIAGRAM", path: "", message: "the diagram could not be read (#{e.class}): check its shape", rule: "crash") ]
    end

    def num(text, allow_inf: false) = Lessons::Num.parse(text, allow_inf: allow_inf)
  end
end
