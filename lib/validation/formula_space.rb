# frozen_string_literal: true

module Validation
  # W-MATH-SPACE-PUNCT (D-335): an inline formula whose TeX ends with a spacing command (\; \, \: \<space> \quad \qquad) and is
  # followed, outside the dollar signs, by a closing mark ($C_3H_6\;$.) shows a gap before the mark. The renderer keeps a mark glued to
  # the formula (items/formula_punct.js), so the spacing is only a gap: the author drops it. Text in, the tex of every such formula out.
  module FormulaSpace
    FORMULA = /\$((?:[^$\\\n]|\\.)+)\$/
    TRAILING_SPACE = /(?:\\[;,: ]|\\q?quad)\s*\z/
    # The marks formula_punct.js keeps next to a formula.
    CLOSING = /\A[.,;:!?)\]»”’"'…]/

    module_function

    # The tex of each inline formula of +text+ that ends in a spacing command right before a closing mark.
    def spaced(text)
      return [] unless text.is_a?(String) && text.include?("$")

      text.to_enum(:scan, FORMULA).filter_map do
        m = Regexp.last_match
        m[1].strip if m[1].match?(TRAILING_SPACE) && m.post_match.match?(CLOSING)
      end
    end

    # +where+ names the place (a field path or a line), as the other warnings do.
    def message(tex, where)
      "#{where}: the formula $#{tex.to_s[0, 40]}$ ends with a spacing command right before a punctuation mark, so the page shows a gap before the mark: drop the spacing (\\;, \\,, \\quad) at the end of the formula, the page already keeps the mark glued to it"
    end
  end
end
