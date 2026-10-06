# frozen_string_literal: true

module Validation
  # What an item's key looks like to a student and to a leak scan: the raw answer
  # the grader would receive for a key or an error value, and the texts that must
  # not appear in what the student reads.
  module Answers
    MIN_LEAK_CHARS = 3
    # Keys that reveal an answer when they appear anywhere in a display (E-DISPLAY-KEY).
    KEY_NAMES = /\A(answers?|keys?|correct|is_?correct|right_answer|solutions?|verdicts?|expected|errors?|rubric|explanation|ok)\z/i

    module_function

    # Rational of a key value (Integer, Float, "3,5", "7/2", {n, d}) or nil.
    def rational(value)
      return value if value.is_a?(Rational)

      Grading::Closed::Numbers.expected_value(value)
    rescue ArgumentError, TypeError, ZeroDivisionError, NoMethodError
      nil
    end

    # "3,5" for a rational that is a finite decimal; nil otherwise.
    def decimal_string(rational)
      den = rational.denominator
      den /= 2 while (den % 2).zero?
      den /= 5 while (den % 5).zero?
      return nil unless den == 1

      scale = 0
      scale += 1 until (rational * (10**scale)).denominator == 1
      digits = (rational.abs * (10**scale)).to_i.to_s.rjust(scale + 1, "0")
      body = scale.zero? ? digits : "#{digits[0...-scale]},#{digits[-scale..]}"
      rational.negative? ? "-#{body}" : body
    end

    # "5,2·10^-4" for a finite decimal (1 <= |a| < 10); "0" for zero; nil otherwise.
    def scientific_string(rational)
      return "0" if rational.zero?

      exponent = 0
      m = rational.abs
      (m /= 10; exponent += 1) while m >= 10
      (m *= 10; exponent -= 1) while m < 1
      mant = decimal_string(rational.negative? ? -m : m)
      mant && "#{mant}\u00B710^#{exponent}"
    end

    # [raw, problem]: the input a student would give for +value+, or a problem
    # description when the value cannot be one for this component.
    def raw_for(component, value, form: [])
      case component
      when "number"
        r = rational(value)
        return [ nil, "the value is not a number" ] unless r

        text = form.include?("scientific") ? scientific_string(r) : decimal_string(r)
        text ? [ text, nil ] : [ nil, "the value is not a finite decimal: use the fraction component" ]
      when "fraction" then fraction_raw(value, form)
      when "expression" then [ value.is_a?(Hash) ? value["latex"].to_s : value.to_s, nil ]
      when "choice" then [ value.to_s, nil ]
      when "ordering" then value.is_a?(Array) ? [ value.map(&:to_s), nil ] : [ nil, "an ordering answer is a list of element ids" ]
      when "matching" then matching_raw(value)
      when "normalized_text" then text_raw(value)
      else [ nil, "no raw form for #{component}" ]
      end
    end

    # A text key must survive the grader's normaliser: one that is only punctuation or
    # invisible characters normalizes to nothing, and no student answer could match it.
    def text_raw(value)
      return [ nil, "a text answer is a non-empty string" ] unless value.is_a?(String) && !value.strip.empty?
      return [ nil, "a text answer that is only punctuation normalizes to nothing: no answer could match it" ] if punctuation_only?(value)

      [ value, nil ]
    end

    def punctuation_only?(text) = Grading::Closed::Text.normalize(text.to_s, case_sensitive: true).empty?

    def fraction_raw(value, form)
      parts =
        if value.is_a?(Hash)
          return [ nil, "a fraction answer has n and d" ] unless value.key?("n") && value.key?("d")

          value
        else
          r = rational(value)
          return [ nil, "the value is not a fraction" ] unless r

          form.include?("mixed") && r.abs >= 1 && r.denominator != 1 ? mixed(r) : { "n" => r.numerator, "d" => r.denominator }
        end
      raw = parts.slice("w", "n", "d").transform_values(&:to_s)
      return [ nil, "the denominator is 0" ] if raw["d"].to_i.zero?

      [ raw, nil ]
    end

    def mixed(r)
      whole = r.abs.floor * (r.negative? ? -1 : 1)
      rest = r.abs - r.abs.floor
      { "w" => whole, "n" => rest.numerator, "d" => rest.denominator }
    end

    def matching_raw(value)
      pairs = value.is_a?(Hash) ? value : (value.is_a?(Array) && value.all? { |p| p.is_a?(Array) && p.size == 2 } ? value.to_h : nil)
      pairs ? [ pairs.to_h { |l, r| [ l.to_s, r.to_s ] }, nil ] : [ nil, "a matching answer maps each left id to a right id" ]
    end

    # The shape of the key against the display it belongs to: [] or problems.
    def shape_problems(component, answer, display)
      case component
      when "choice"
        ids = Array(display["options"]).map { |o| o["id"] }
        ids.include?(answer.to_s) ? [] : [ "the key #{answer.inspect} is not one of the option ids" ]
      when "ordering"
        ids = Array(display["elements"]).map { |o| o["id"] }
        answer.is_a?(Array) && answer.map(&:to_s).sort == ids.sort ? [] : [ "the key is not a permutation of the element ids" ]
      when "matching"
        left = Array(display["left"]).map { |o| o["id"] }
        right = Array(display["right"]).map { |o| o["id"] }
        pairs = matching_raw(answer).first
        if pairs.nil? || pairs.keys.sort != left.sort || !(pairs.values - right).empty?
          [ "the key must pair every left id with a right id" ]
        elsif display["reuse_right"] == true
          pairs.values.uniq.size >= 2 ? [] : [ "a classification key uses at least 2 different categories" ]
        elsif pairs.values.uniq.size != pairs.size
          [ "the key must pair every left id with its own right id (set display.reuse_right for a classification)" ]
        else
          []
        end
      else
        _raw, problem = raw_for(component, answer)
        problem ? [ problem ] : []
      end
    end

    # ---- leak scan ----------------------------------------------------------

    # Whitespace, \left/\right, a product dot and the braces of a one-token exponent
    # are not part of what a reader sees as the same expression: x^{2}y, x^2y, 4\cdot x^2y.
    def squash(text)
      text.to_s.unicode_normalize(:nfkc).downcase.gsub(/[[:space:]]+/, "").gsub(/\\(left|right)/, "")
          .gsub(/\\(?:cdot|times)|\*/, "").gsub(/\^\{([[:alnum:]]+)\}/, '^\1').gsub(/\^\(([[:alnum:]]+)\)/, '^\1')
    end
    def plain(text) = text.to_s.unicode_normalize(:nfkc).downcase.gsub(/[[:space:]]+/, " ").strip

    # Does +needle+ occur in +haystack+ as a whole token (not inside a longer word
    # or number)? Also tried with the spaces removed, for mathematics.
    def contains?(haystack, needle)
      n = plain(needle)
      return false if n.length < MIN_LEAK_CHARS

      token_match?(plain(haystack), n) || (squash(needle).length >= MIN_LEAK_CHARS && token_match?(squash(haystack), squash(needle)))
    end

    def token_match?(haystack, needle)
      haystack.match?(/(?<![[:alnum:]])(?<![,.]\d)(?<!\d\.)#{Regexp.escape(needle)}(?![[:alnum:]])(?![,.]\d)/)
    end

    # The key texts of a (non-choice) instance, long enough to be a leak.
    def key_texts(component, answer, accept: [])
      texts =
        case component
        when "number"
          r = rational(answer)
          [ r && decimal_string(r), r && scientific_string(r) ] + accept.map { |a| (x = rational(a)) && decimal_string(x) }
        when "fraction"
          r = rational(answer.is_a?(Hash) ? { "n" => answer["n"], "d" => answer["d"] } : answer)
          r ? [ "#{r.numerator}/#{r.denominator}", "#{r.numerator} / #{r.denominator}", "\\frac{#{r.numerator}}{#{r.denominator}}" ] : []
        when "expression" then [ answer.is_a?(Hash) ? answer["latex"] : answer ]
        when "normalized_text" then [ answer ] + accept
        else []
        end
      texts.compact.map(&:to_s).select { |t| plain(t).length >= MIN_LEAK_CHARS }
    end

    # Names that reveal an answer, anywhere in a display: [[path, name]].
    def display_keys(node, path = "", out = [])
      case node
      when Hash
        node.each do |k, v|
          out << [ "#{path}/#{k}", k.to_s ] if k.to_s.match?(KEY_NAMES)
          display_keys(v, "#{path}/#{k}", out)
        end
      when Array then node.each_with_index { |v, i| display_keys(v, "#{path}/#{i}", out) }
      end
      out
    end
  end
end
