# frozen_string_literal: true

module Lessons
  # Leak rules L4 and L5 of WAVE2 1.4, on one card: a text-answer check must not ask what a figure of the same card prints (W-CHECK-ANSWER-IN-DIAGRAM,
  # from the type's `printed` in every state), nor what an interactive figure can be made to show inside its declared ranges
  # (E-CHECK-ANSWER-BY-SIMULATION, from `reachable`; E-DIAGRAM-REACHABLE-CAP when there are more than 500 outputs). The only way past L5 is
  # `reachable_ok_it` on the check. A type whose Ruby module is not built answers nothing (its figure cannot be in a stored lesson anyway).
  module Leaks
    Finding = Data.define(:code, :path, :message, :rule)

    module_function

    # card: a card of the body; base: its JSON pointer ("/cards/3"). The findings, with the pointer of the check or the figure.
    def card(card, base)
      diagrams = []
      checks = []
      walk(card["blocks"], "#{base}/blocks", diagrams, checks)
      return [] if diagrams.empty? || checks.empty?

      out = []
      diagrams.each do |dpath, d|
        mod = module_of(d["type"])
        next unless mod

        printed = tokens(d) { |i| mod.printed(d, i) }
        reach = begin
          mod.reachable(d)
        rescue NotImplementedError
          []
        end
        out << Finding.new("E-DIAGRAM-REACHABLE-CAP", dpath, "the figure can show more than #{Diagrams::Contract::REACHABLE_CAP} values and a check is on the same card: narrow its ranges or move the check", "reach-cap#{dpath}") if reach == :over_cap
        reachable = reach == :over_cap ? [] : reach.map { |s| norm(s) }.to_set
        checks.each do |cpath, c|
          next unless c["answer"].is_a?(String)

          answer = norm(c["answer"])
          next if answer.empty?

          out << Finding.new("W-CHECK-ANSWER-IN-DIAGRAM", "#{cpath}/answer", "the answer #{c['answer'].inspect} is printed by the #{d['type']} of the same card", "in-diagram#{cpath}#{dpath}") if printed.include?(answer)
          next unless reachable.include?(answer) && c["reachable_ok_it"].to_s.strip.empty?

          out << Finding.new("E-CHECK-ANSWER-BY-SIMULATION", "#{cpath}/answer", "the answer #{c['answer'].inspect} is a value the #{d['type']} of the same card can be made to show; say why it does not give the answer away in reachable_ok_it, or move the check", "simulation#{cpath}#{dpath}")
        end
      end
      out
    end

    def module_of(type)
      return unless Types.available?(:diagram, type) && Diagrams::TYPES.key?(type)

      mod = Diagrams.const_get(Diagrams::TYPES.fetch(type))
      mod.respond_to?(:printed) ? mod : nil
    end

    # The printed tokens of every state of a figure, normalized.
    def tokens(diagram)
      count = [ Array(diagram["states"]).size, 1 ].max
      (0...count).flat_map { |i| yield(i) }.map { |s| norm(s) }.to_set
    rescue NotImplementedError
      Set.new
    end

    # "-5", "−5", "0010 1101" and "00101101" are the same answer to the eye.
    def norm(text) = text.to_s.gsub(/[[:space:]]/, "").tr("\u2212", "-").downcase

    def walk(node, path, diagrams, checks)
      case node
      when Hash
        diagrams << [ path, node ] if node["type"].is_a?(String) && node.key?("alt_it") && Diagrams::TYPES.key?(node["type"])
        checks << [ path, node ] if node["component"].is_a?(String) && node.key?("answer")
        node.each { |k, v| walk(v, "#{path}/#{k}", diagrams, checks) if v.is_a?(Hash) || v.is_a?(Array) }
      when Array
        node.each_with_index { |v, i| walk(v, "#{path}/#{i}", diagrams, checks) }
      end
    end
  end
end
