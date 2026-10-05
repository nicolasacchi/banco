# frozen_string_literal: true

module Validation
  # The readability lint of the Italian text an agent writes (A-06, the item brief
  # rule 6): every string under a key that ends in `_it`. Texts in the language
  # being taught (option texts, table cells, quotes) are not under such keys and
  # are not linted. Thresholds: config/banco/validation_rules.yml.
  #
  # Errors (E-READ with a rule name, E-PHRASE, E-MESSAGE) block approval;
  # warnings (W-GULPEASE, W-PASSAGE-READABILITY, W-ABSOLUTE, W-NEGATIVE-STEM,
  # W-DECIMAL-POINT, W-SELF-CERT) are shown to the reviewer and the teacher.
  module Readability
    MATH = /\$\$.+?\$\$|\$[^$\n]+\$/m
    BOLD = /\*\*(.+?)\*\*/m
    WORD = /[\p{L}\p{N}][\p{L}\p{N}'’_-]*/
    EMOJI = /[\u{1F000}-\u{1FAFF}\u{21A0}-\u{21FF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}\u{20E3}]/
    ABBREVIATIONS = /(?:\b(?:m\.c\.m|m\.c\.d|c\.e)\.|(?<![-\p{L}])\b(?:ecc|es|sig|sigg|dott|prof|art|artt|pag|pagg|cfr|vs|n|nn|p\.es)\.)/i
    ROMAN = /\A[IVXLCDM]+\z/

    module_function

    # Lints one text. role: :stem, :message, :passage or :text.
    def lint(text, field:, role:, findings:)
      return unless text.is_a?(String)

      plain = text.gsub(MATH, " m ")
      markup(plain, field, findings)
      emoji(plain, field, findings)
      caps(plain, field, findings)
      bold(text.gsub(MATH, " m "), field, findings)
      phrases(text, field, findings)
      sentences = sentences_of(strip_markup(plain))
      words = sentences.sum { |s| s.scan(WORD).size }
      max = Rules.get(:readability, :max_sentence_words)
      long = sentences.map { |s| s.scan(WORD).size }.max.to_i
      findings.add("E-READ", field, "a sentence has #{long} words (at most #{max})", rule: "sentence_length", words: long) if long > max
      if role == :stem && words > Rules.get(:readability, :max_stem_words)
        findings.add("E-READ", field, "the instruction has #{words} words (at most #{Rules.get(:readability, :max_stem_words)})", rule: "stem_length", words: words)
      end
      if role == :message && sentences.size > Rules.get(:readability, :max_message_sentences)
        findings.add("E-MESSAGE", field, "the message has #{sentences.size} sentences (at most #{Rules.get(:readability, :max_message_sentences)})", sentences: sentences.size)
      end
      warnings(text, plain, sentences, words, field, role, findings)
    end

    # Walks a parsed JSON value and lints every *_it string by its key.
    def lint_document(node, path, findings)
      case node
      when Hash
        node.each do |key, value|
          field = "#{path}/#{key}"
          if value.is_a?(String) && key.to_s.end_with?("_it")
            lint(value, field: field, role: role_for(key.to_s), findings: findings)
          elsif key.to_s != "quote"
            lint_document(value, field, findings)
          end
        end
      when Array
        node.each_with_index { |v, i| lint_document(v, "#{path}/#{i}", findings) }
      end
    end

    def role_for(key)
      case key
      when "stem_it" then :stem
      when "message_it" then :message
      when "passage_it" then :passage
      else :text
      end
    end

    # ---- rules ---------------------------------------------------------------

    def markup(plain, field, findings)
      bad =
        if plain.match?(/<\/?[a-zA-Z!][^>]*>/) then "an HTML tag"
        elsif plain.match?(/(?<![*\w])\*(?![*\s])[^*\n]+?(?<![*\s])\*(?!\*)/) then "italics"
        elsif plain.match?(/(?<![\w])_(?![_\s])[^_\n]+?(?<![_\s])_(?![\w])/) then "italics"
        elsif plain.match?(/^\s{0,3}\#{1,6}\s/) then "a heading"
        elsif plain.match?(/`/) then "code quotes"
        elsif plain.match?(/\]\(/) || plain.match?(/\bhttps?:\/\//) then "a link"
        elsif plain.match?(/^\s*[-*+]\s+\S/) then "a bullet list (numbered lists only)"
        elsif plain.match?(/\|/) then "a table"
        elsif plain.match?(/~~/) then "strike-through"
        end
      findings.add("E-READ", field, "markup outside the allowed set (#{bad}): only **bold**, $math$, paragraphs and numbered lists", rule: "markup") if bad
    end

    def emoji(plain, field, findings)
      findings.add("E-READ", field, "an emoji or pictogram", rule: "emoji") if plain.match?(EMOJI)
    end

    def caps(plain, field, findings)
      allowed = Rules.list(:readability, :caps_allowlist)
      # A spreadsheet function name (SOMMA(, CONTA.SE) is a name, not shouting (D-095).
      word = plain.scan(/\p{L}+(?![(\p{L}]|\.\p{L})/).find do |w|
        w.length >= 3 && w == w.upcase && w != w.downcase && !allowed.include?(w) && !w.match?(ROMAN)
      end
      findings.add("E-READ", field, "an ALL-CAPS word (#{word})", rule: "all_caps", word: word) if word
    end

    def bold(plain, field, findings)
      spans = plain.scan(BOLD).flatten
      max = Rules.get(:readability, :max_bold_spans)
      findings.add("E-READ", field, "#{spans.size} bold spans (at most #{max})", rule: "bold_spans", count: spans.size) if spans.size > max
      longest = spans.map { |s| s.scan(WORD).size }.max.to_i
      max_words = Rules.get(:readability, :max_bold_span_words)
      findings.add("E-READ", field, "a bold span has #{longest} words (at most #{max_words})", rule: "bold_span_length", words: longest) if longest > max_words
    end

    def phrases(text, field, findings)
      lower = text.downcase
      Rules.list(:readability, :banned_phrases).each do |phrase|
        findings.add("E-PHRASE", field, "banned phrase: #{phrase}", rule: phrase) if lower.match?(/(?<![[:alnum:]])#{Regexp.escape(phrase)}(?![[:alnum:]])/)
      end
    end

    def warnings(text, plain, sentences, words, field, role, findings)
      body = strip_markup(plain)
      if role == :passage
        index = gulpease(body, sentences, words)
        if index && index < Rules.get(:readability, :passage_min_gulpease)
          findings.add("W-PASSAGE-READABILITY", field, "the passage has a Gulpease index of #{index.round} (below #{Rules.get(:readability, :passage_min_gulpease)})", index: index.round)
        end
      elsif words >= Rules.get(:readability, :min_gulpease_words)
        index = gulpease(body, sentences, words)
        if index && index < Rules.get(:readability, :min_gulpease)
          findings.add("W-GULPEASE", field, "Gulpease index #{index.round} (below #{Rules.get(:readability, :min_gulpease)})", index: index.round)
        end
      end
      lower = body.downcase.gsub(/\bda (?:solo|sola|soli|sole)\b/, " ")   # "by oneself", not "only" (D-094)
      if (w = Rules.list(:readability, :absolute_words).find { |a| lower.match?(/\b#{Regexp.escape(a)}\b/) })
        findings.add("W-ABSOLUTE", field, "an absolute word (#{w}) needs a counterexample check", word: w)
      end
      # A negation inside «…» or $…$ is the content being asked about, not the instruction.
      instruction = lower.gsub(/«[^»]*»/, " ").gsub(/\$[^$]*\$/, " ")
      if role == :stem && Rules.list(:readability, :negative_stem).any? { |re| instruction.match?(Regexp.new(re)) }
        findings.add("W-NEGATIVE-STEM", field, "the instruction is phrased as a negation")
      end
      if body.match?(/\d\.\d{1,2}(?!\d)/)
        findings.add("W-DECIMAL-POINT", field, "a decimal point where the Italian comma is expected")
      end
      if Rules.list(:readability, :self_cert).any? { |re| lower.match?(Regexp.new(re)) }
        findings.add("W-SELF-CERT", field, "self-certifying wording")
      end
    end

    # ---- helpers ---------------------------------------------------------------

    def strip_markup(text) = text.gsub(BOLD, '\1').gsub(/^\s*\d+\.\s+/, "")

    # Sentences, with the usual abbreviations protected from the split.
    def sentences_of(text)
      protected = text.gsub(ABBREVIATIONS) { |m| m.tr(".", "\u0001") }
      protected.split(/(?<=[.!?…])\s+|\n+/).map { |s| s.tr("\u0001", ".").strip }.reject { |s| s.scan(WORD).empty? }
    end

    # The Gulpease index: 89 + (300 * sentences - 10 * letters) / words.
    def gulpease(body, sentences, words)
      return nil if words.zero? || sentences.empty?

      letters = body.scan(/\p{L}/).size
      89 + (300.0 * sentences.size - 10.0 * letters) / words
    end
  end
end
