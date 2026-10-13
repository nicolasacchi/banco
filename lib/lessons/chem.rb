# frozen_string_literal: true

module Lessons
  # Chem: the formula grammar (case-exact symbols from chem/elements, one bracket level), atom counts and classes (WAVE2 1.10, 2.8; T7).
  # The JS twin is app/javascript/lesson/lib/chem.js and both run test/fixtures/lesson2/chem_formulas.json (like Lessons::Num and lesson/num.js).
  #
  #   formula   := coefficient? unit state?
  #   coefficient := 2..20, then an optional single space        ("3 H2O", "2Ca(NO3)2")
  #   unit      := ( Symbol subscript? | "(" ( Symbol subscript? )+ ")" subscript )+
  #   subscript := 2..99 (a 1 is never written)
  #   state     := "(s)" | "(l)" | "(g)" | "(aq)"
  #
  # Symbols are the 118 of chem/elements and are case-exact: "Co" is cobalt, "CO" is carbon and oxygen, "CL" is nothing. One level of
  # brackets in this release; charges and hydrates come later. Nothing here draws or says anything: that is the figure's job.
  module Chem
    NotBuilt = Class.new(NotImplementedError)
    # name => signature (Ruby)
    SIGNATURES = {
      "parse" => "parse(formula)",
      "count" => "count(formula)",
      "classify" => "classify(formula)",
      "same_composition" => "same_composition(a, b)"
    }.freeze
    COEFFICIENT = (2..20)
    SUBSCRIPT = (2..99)
    STATES = %w[s l g aq].freeze

    module_function

    # The 118 symbols, case-exact.
    def symbols = (@symbols ||= VettedData.table("chem/elements").fetch("elements").map { |e| e["symbol"] }.to_set.freeze)

    def symbol?(text) = symbols.include?(text.to_s)

    # The row of an element by symbol, or nil.
    def element(symbol) = (@rows ||= VettedData.table("chem/elements").fetch("elements").to_h { |e| [ e["symbol"], e ] }.freeze)[symbol.to_s]

    # A formula as {"coefficient", "groups", "state"}; nil when it does not parse. A group is {"symbol", "count"} or, for a bracket group,
    # {"group" => [{"symbol", "count"}...], "count"}. The coefficient is 1 when none is written; the state is nil or "aq" etc.
    def parse(formula)
      text = formula.to_s
      return nil if text.empty? || text.strip != text

      coefficient = 1
      if (m = text.match(/\A(\d+) ?/))
        coefficient = m[1].to_i
        return nil unless m[1] == coefficient.to_s && COEFFICIENT.cover?(coefficient)

        text = text[m[0].size..]
      end
      state = nil
      if (m = text.match(/\((s|l|g|aq)\)\z/))
        state = m[1]
        text = text[0...(text.size - m[0].size)]
      end
      groups = []
      i = 0
      while i < text.size
        if text[i] == "("
          close = text.index(")", i)
          return nil unless close

          inner = atoms(text[(i + 1)...close]) or return nil
          return nil if inner.empty?

          n = subscript(text, close + 1) or return nil
          return nil unless n[:count]

          groups << { "group" => inner, "count" => n[:count] }
          i = n[:next]
        else
          one = atom(text, i) or return nil
          groups << { "symbol" => one[:symbol], "count" => one[:count] }
          i = one[:next]
        end
      end
      return nil if groups.empty?

      { "coefficient" => coefficient, "groups" => groups, "state" => state }
    end

    # Atoms by symbol, coefficient included; nil when the formula does not parse.
    def count(formula)
      parsed = parse(formula) or return nil
      totals = Hash.new(0)
      parsed["groups"].each do |g|
        if g["group"]
          g["group"].each { |a| totals[a["symbol"]] += a["count"] * g["count"] * parsed["coefficient"] }
        else
          totals[g["symbol"]] += g["count"] * parsed["coefficient"]
        end
      end
      totals
    end

    # "element" when one kind of atom makes the formula, "compound" otherwise; nil when it does not parse.
    def classify(formula)
      totals = count(formula) or return nil
      totals.size == 1 ? "element" : "compound"
    end

    # Whether two formulas have the same atom counts (a near miss of a typed answer); false when either does not parse.
    def same_composition(a, b)
      ca = count(a)
      cb = count(b)
      !ca.nil? && !cb.nil? && ca == cb
    end

    # The formula without its coefficient and state ("2 Ca(NO3)2(aq)" -> "Ca(NO3)2"), the key of chem/molecules; nil when it does not parse.
    def base(formula)
      return nil unless parse(formula)

      formula.to_s.sub(/\A\d+ ?/, "").sub(/\((s|l|g|aq)\)\z/, "")
    end

    # The first symbol of text[i..] that is an element, longest first; nil when none.
    def symbol_at(text, i)
      return nil unless text[i]&.match?(/[A-Z]/)

      [ 3, 2, 1 ].each do |len|
        candidate = text[i, len]
        next unless candidate.size == len && candidate.match?(/\A[A-Z][a-z]*\z/)

        return candidate if symbols.include?(candidate)
      end
      nil
    end

    # The first symbol-shaped word of the text (a capital and its lowercase letters) that is not an element: "Xx2" gives "Xx", "CL2" gives
    # "L" (C is fine, L is nothing); nil when every such word is an element (the formula may still be badly shaped).
    def unknown_symbol(formula)
      formula.to_s.scan(/[A-Z][a-z]*/).find { |word| !symbols.include?(word) }
    end

    def atom(text, i)
      sym = symbol_at(text, i) or return nil
      sub = subscript(text, i + sym.size) or return nil
      { symbol: sym, count: sub[:count] || 1, next: sub[:next] }
    end

    def atoms(text)
      out = []
      i = 0
      while i < text.size
        one = atom(text, i) or return nil
        out << { "symbol" => one[:symbol], "count" => one[:count] }
        i = one[:next]
      end
      out
    end

    # {count: Integer or nil, next: Integer} for the digits at text[i..]; nil when they are not a legal subscript (a leading 0, a 1, over 99).
    def subscript(text, i)
      m = text[i..].to_s.match(/\A\d+/)
      return { count: nil, next: i } unless m
      return nil unless m[0].match?(/\A[1-9]\d*\z/)

      n = m[0].to_i
      return nil unless SUBSCRIPT.cover?(n)

      { count: n, next: i + m[0].size }
    end
    private_class_method :atom, :atoms, :subscript
  end
end
