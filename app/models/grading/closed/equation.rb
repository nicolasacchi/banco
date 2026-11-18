module Grading
  module Closed
    # An answer written in full (D-362): «x = 7,4», «5+4 = 9», «5+4 = 9 = 9». The text is split at its top-level `=` into members;
    # the last one is the answer and is graded as if it stood alone (a wrong value stays wrong, with its error code), the first is
    # the left side. A left side is accepted when it is one Latin letter (the unknown, D-295) or the expression the student was
    # shown (Spec#stem_expressions, compared in a plain form); in a chain (three members or more) a first member that equals the
    # key is accepted too, and every member before the last must equal the key. A left side that is another expression is never
    # accepted. No I/O.
    module Equation
      LETTER = /\A[A-Za-z]\z/
      # A relation in a shown text: not an expression, never the left side.
      RELATION = /[=<>≤≥≠]/
      LATEX_SPACING = /\\(?:left|right|,|;|:|!| |quad|qquad|displaystyle|textstyle)/

      module_function

      # The members of +text+ cut at its top-level `=` (not inside brackets, not the `=` of <=, >=, !=, :=, ==), trimmed; nil when
      # there is no `=`, a member is empty or the brackets do not close. A text that is not a String has no members.
      def members(text)
        return nil unless text.is_a?(String) && text.include?("=")

        parts = []
        depth = 0
        start = 0
        text.each_char.with_index do |char, i|
          case char
          when "(", "[", "{" then depth += 1
          when ")", "]", "}"
            depth -= 1
            return nil if depth.negative?
          when "="
            next unless depth.zero?
            next if (i.positive? && "<>!:=".include?(text[i - 1])) || text[i + 1] == "="

            parts << text[start...i]
            start = i + 1
          end
        end
        return nil unless depth.zero? && parts.any?

        members = (parts << text[start..]).map { |m| Numbers.clean(m) }
        members.all?(&:present?) ? members : nil
      end

      # The first member of an answer written in full: the unknown's letter, or an expression the item shows.
      def left_side?(spec, member)
        member.match?(LETTER) || shown?(spec, member)
      end

      def shown?(spec, member)
        key = plain(member)
        spec.stem_expressions.any? { |stem| !stem.match?(RELATION) && plain(stem) == key }
      end

      # A text of arithmetic, in LaTeX or as typed, in one form: the spaces, the product and division signs, the minus, the
      # decimal comma, the superscripts, the roots, \frac and the brackets around one token or the whole made plain.
      def plain(text)
        s = Numbers.clean(text).gsub(LATEX_SPACING, "")
        s = s.gsub(/\^\{(\d+)\}/, '^\1').gsub(/[⁰¹²³⁴⁵⁶⁷⁸⁹]+/) { |m| "^#{m.tr(Numbers::SUPERSCRIPTS, '0123456789')}" }
        s = s.gsub(/\\(?:cdot|times)(?![A-Za-z])/, "*").gsub(/\\div(?![A-Za-z])/, "/").gsub(/[·⋅×]/, "*").gsub(/[÷:]/, "/")
        4.times { s = s.gsub(/\\frac\{([^{}]*)\}\{([^{}]*)\}/, '(\1)/(\2)') }
        s = s.gsub(/\\(?:sqrt|surd)(?![A-Za-z])|√/, "sqrt").tr("{}[]", "()()")
        s = s.gsub(/(\d),(?=\d)/, '\1.').gsub(Numbers::SPACES, "")
        s = s.gsub(/\(([A-Za-z0-9.]+)\)/, '\1')
        s = s[1..-2] while wrapped?(s)
        s
      end

      # «(5+4)»: one pair of brackets around the whole text, the first one closed by the last character.
      def wrapped?(s)
        return false unless s.start_with?("(") && s.end_with?(")")

        depth = 0
        s.each_char.with_index do |char, i|
          depth += 1 if char == "("
          depth -= 1 if char == ")"
          return false if depth.zero? && i < s.length - 1
        end
        true
      end
    end
  end
end
