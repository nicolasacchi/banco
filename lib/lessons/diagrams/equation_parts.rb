# frozen_string_literal: true

module Lessons
  module Diagrams
    # The anatomy of an equation: parts in order (the members and the =), brackets over whole parts.
    module EquationParts
      module_function

      def static(data, c)
        parts = data["parts"].to_a
        parts.each_with_index do |part, i|
          c.role("/parts/#{i}/role", part["role"]) if part["role"]
          c.label("/parts/#{i}/label_it", part["label_it"])
          c.tex("/parts/#{i}/tex", part["tex"])
        end
        return if c.findings.any? { |f| f.path.start_with?("/parts") }

        joined = parts.map { |p| p["tex"] }.join(" ")
        return if balanced?(joined)

        c.diagram("/parts", "the parts joined are not a valid formula of the markup grammar (unbalanced braces or a dangling command)", rule: "joined")
      end

      def balanced?(tex)
        depth = 0
        stripped = tex.gsub(/\\[{}]/, "")
        stripped.each_char do |ch|
          depth += 1 if ch == "{"
          depth -= 1 if ch == "}"
          return false if depth.negative?
        end
        depth.zero? && !tex.rstrip.end_with?("\\") && tex.scan(/\\left(?![A-Za-z])/).size == tex.scan(/\\right(?![A-Za-z])/).size
      end

      def state(eff, c, path)
        count = eff["parts"].to_a.size
        eff["brackets"].to_a.each_with_index do |b, i|
          at = "#{path}/brackets/#{i}"
          c.role("#{at}/role", b["role"]) if b["role"]
          c.label("#{at}/label_it", b["label_it"])
          if b["to"] >= count
            c.diagram("#{at}/to", "brackets cover whole parts that exist: part #{b['to']} of #{count}", rule: "bracket-to#{at}")
          elsif b["from"] > b["to"]
            c.diagram(at, "a bracket goes from a part to a later or the same part", rule: "bracket-order#{at}")
          end
        end
      end
    end
  end
end
