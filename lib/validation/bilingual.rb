# frozen_string_literal: true

module Validation
  # The checks of the bilingual courses of english and spanish (D-402, §4.2), shared by the item, lesson, course, graph and topic checks.
  # A bilingual revision writes every student text twice: the target language under `<base>_en|_es` and its Italian under `<base>_it`.
  # `Lessons::Bilingual.pairs` walks the pairs; this module decides what is wrong with each:
  #
  #   E-LANG-PAIR-MISSING / -ORPHAN   a text without its translation, a translation without its text, lists of different length
  #   E-LANG-PAIR-SHAPE               paragraphs, list items, ___ blanks, math, digits, bold words, [[g:..]] terms differ
  #   E-LANG-PAIR-CONFLICT            two equal target strings in one scope with different Italian
  #   E-LANG-TRANSLATION-LANG         an `_it` text that is not Italian; E-LESSON-LANG for a `_en|_es` text that is Italian
  #   E-LANG-TRANSLATION-COPY         an `_it` text equal to its target text
  #   E-LANG-BILINGUAL-FLAG / -REQUIRED   the `bilingual` marker (flag) and the rule that asks for it (required)
  #
  # plus the lint of the target-language texts (12-word sentences, the 60-word stem, W-LANG-LEVEL with the given names allowed) and the
  # target layer of a document: the document with each target text under its legacy `_it` key, which the checks written before D-402 read.
  module Bilingual
    # Bases whose `_en` key is not a translated text (a vocabulary list the lesson teaches).
    NOT_TEXT = (Lessons::Bilingual::FIELDS[:target_only] + Lessons::Bilingual::FIELDS[:native] + Lessons::Bilingual::EXEMPT).freeze
    SPAN = /\[\[(?:en|es|la|code):.*?\]\](?!\])/m
    QUOTED = /«[^»]*»|"[^"]*"|“[^”]*”/
    LIST_ITEM = /^[ \t]*(?:[-*]|\d+[.)])[ \t]+/
    DIGITS = /\d[\d.,]*/
    NAMES_DIR = Lessons::Lexicon::DIR

    module_function

    def bilingual?(doc) = doc.is_a?(Hash) && doc["bilingual"] == true

    # ---- the walk -------------------------------------------------------------------------------------------------------------

    # Adds the findings of every pair of +doc+ (a body, a block, an item, a front matter) to +findings+. +lang+ is the subject's language;
    # +prefix+ goes before each pointer; +line+ (a pointer -> Integer or nil) puts a line in the detail; +skip+ (pointer, base -> true) leaves a pair
    # to the caller; +conflicts+ is off for an item (its instances are not one translation table). Returns +findings+.
    def check(findings, doc, lang:, prefix: "", line: nil, skip: nil, conflicts: true, r2: true)
      table = {}
      Lessons::Bilingual.pairs(doc, lang) do |pointer, base, target, italian|
        next if skip&.call(pointer, base)
        next unless (target.nil? || target.is_a?(String)) && (italian.nil? || italian.is_a?(String))

        field = "#{prefix}#{pointer}"
        at = line ? { line: line.call(pointer) }.compact : {}
        target = nil if target.to_s.strip.empty?
        italian = nil if italian.to_s.strip.empty?
        pair_lang = lang || pointer[/_(en|es)(?:\/\d+)*\z/, 1]
        add = ->(code, message) { findings.add(code, field, message, rule: "#{code}-#{field}", **at) }

        if target.nil? && italian.nil?
          next
        elsif italian.nil?
          add.call("E-LANG-PAIR-MISSING", "#{base} has its #{pair_lang || 'target-language'} text but no Italian translation (#{base}_it)")
        elsif target.nil?
          add.call(pointer.match?(%r{/\d+\z}) ? "E-LANG-PAIR-MISSING" : "E-LANG-PAIR-ORPHAN",
                   pointer.match?(%r{/\d+\z}) ? "#{base}_it has more entries than #{base}_#{pair_lang} (a list and its translation have the same length)" : "#{base}_it has no #{base}_#{pair_lang || 'en'} text to translate")
        else
          shape_problems(target, italian).each { |problem| add.call("E-LANG-PAIR-SHAPE", "#{base}: the translation differs in shape: #{problem}") }
          add.call("E-LESSON-LANG", "#{base}_#{pair_lang} holds Italian words (a key ending in _#{pair_lang} holds that language only)") if %w[en es].include?(pair_lang) && Lessons::Lang.italian?(target)
          add.call("E-LANG-TRANSLATION-LANG", "#{base}_it is not Italian: it holds words of #{pair_lang == 'es' ? 'Spanish' : 'English'}") if translation_lang?(italian, pair_lang)
          add.call("E-LANG-TRANSLATION-COPY", "#{base}_it is the same text as #{base}_#{pair_lang}: write the translation") if copy?(target, italian)
          conflict(findings, table, field, target, italian, at) if conflicts
        end
      end
      r2_gaps(doc) do |pointer, base|
        next if skip&.call(pointer, base)

        findings.add("E-LANG-PAIR-MISSING", "#{prefix}#{pointer}", "#{base} has no Italian translation (#{base}_it beside it)", rule: "E-LANG-PAIR-MISSING-#{prefix}#{pointer}", **(line ? { line: line.call(pointer) }.compact : {}))
      end if r2
      findings
    end

    # The fields of rule R2 (an option's `text`, a table's `header` and `rows`, `quote.text`, a solution's `final`) hold the target text under the bare
    # key: `Lessons::Bilingual.pairs` meets them only through their `_it` twin, so a bare key with no twin is found here: yields (pointer, base).
    def r2_gaps(node, pointer = "", &block)
      case node
      when Hash
        Lessons::Bilingual::FIELDS[:r2].each do |base, where|
          value = node[base]
          next unless where.match?(pointer) && !node.key?("#{base}_it") && (value.is_a?(String) ? !value.strip.empty? : value.is_a?(Array) && value.any?)

          yield "#{pointer}/#{base}", base
        end
        node.each { |k, v| r2_gaps(v, "#{pointer}/#{k}", &block) if v.is_a?(Hash) || v.is_a?(Array) }
      when Array then node.each_with_index { |v, i| r2_gaps(v, "#{pointer}/#{i}", &block) if v.is_a?(Hash) || v.is_a?(Array) }
      end
    end

    def conflict(findings, table, field, target, italian, at)
      key = plain(target)
      first = table[key]
      if first.nil?
        table[key] = [ italian, field ]
      elsif plain(first[0]) != plain(italian)
        findings.add("E-LANG-PAIR-CONFLICT", field, "the same text has another translation at #{first[1]}: the translation table is keyed by the target text, so write one Italian for it", rule: "conflict-#{field}", **at)
      end
    end

    # ---- shape parity ---------------------------------------------------------------------------------------------------------

    # What differs, in words, between a target text and its translation: [] when the two have the same shape.
    def shape_problems(target, italian)
      out = []
      count = ->(label, a, b) { out << "#{a} #{label} in the text, #{b} in the translation" if a != b }
      count.call("paragraphs", paragraphs(target), paragraphs(italian))
      count.call("list items", target.scan(LIST_ITEM).size, italian.scan(LIST_ITEM).size)
      count.call("___ blanks", target.scan(/_{2,}/).size, italian.scan(/_{2,}/).size)
      count.call("**bold** words", target.scan(/\*\*(.+?)\*\*/m).size, italian.scan(/\*\*(.+?)\*\*/m).size)
      count.call("[[g:..]] terms", target.scan(/\[\[g:/).size, italian.scan(/\[\[g:/).size)
      maths = [ math_of(target), math_of(italian) ]
      out << "the math differs (#{(maths[0] - maths[1]).first(2).join(', ')} / #{(maths[1] - maths[0]).first(2).join(', ')})" if maths[0].sort != maths[1].sort
      digits = [ digits_of(target), digits_of(italian) ]
      out << "the numbers differ (#{(digits[0] - digits[1]).first(3).join(', ')} / #{(digits[1] - digits[0]).first(3).join(', ')})" if digits[0].sort != digits[1].sort
      out
    end

    def paragraphs(text) = text.split(/\n[ \t]*\n/).count { |p| !p.strip.empty? }

    def math_of(text) = text.scan(Readability::MATH).map { |m| m.gsub(/\s+/, "") }

    # Digit runs outside math, without the thousands and decimal marks (3.5 and 3,5, 1,000 and 1.000 read the same).
    def digits_of(text) = text.gsub(Readability::MATH, " ").scan(DIGITS).map { |d| d.delete(".,") }.reject(&:empty?)

    # ---- the language of the two texts ------------------------------------------------------------------------------------------

    # The words of +text+ the way the language checks read them: markup and spans reduced to their words, math dropped, lower case.
    def plain(text)
      text.to_s.gsub(Readability::MATH, " ")
          .gsub(/\[\[code:.*?\]\](?!\])/m, " ")
          .gsub(/\[\[(?:[a-z]+(?:[_-][a-z]+)*)(?:\|it)?:(.*?)\]\](?!\])/m, '\1')
          .gsub(/\[([^\[\]]*)\]\((?:scheda|argomento):[^()]*\)/, '\1')
          .delete("*_").downcase.gsub(/[[:space:]]+/, " ").strip
    end

    # True when an Italian text holds two distinct function words of the target language outside spans and quotations (a translation that was
    # not translated). +lang+ nil reads both lists.
    def translation_lang?(italian, lang)
      outside = italian.to_s.gsub(SPAN, " ").gsub(QUOTED, " ").gsub(Readability::MATH, " ")
      words = outside.downcase.scan(/\p{L}+/)
      lists = lang ? [ Lessons::Lang::TARGET_WORDS.fetch(lang, []) ] : Lessons::Lang::TARGET_WORDS.values
      lists.any? { |list| (words & list).size >= 2 }
    end

    # True when the Italian is the target text itself (after spans and markup) and holds a word of four or more letters.
    def copy?(target, italian)
      a = plain(target)
      a == plain(italian) && a.match?(/\p{L}{4,}/)
    end

    # ---- the marker -----------------------------------------------------------------------------------------------------------------

    # E-LANG-BILINGUAL-FLAG: the marker in a subject that does not teach a language, a sibling of the subject's language with the marker off,
    # a sibling of another language than the subject's. +doc+ is the whole document (the siblings are looked for in it).
    def flag(findings, doc, subject:, prefix: "", line: nil)
      lang = Lessons::Lang.target(subject)
      if bilingual?(doc) && lang.nil?
        findings.add("E-LANG-BILINGUAL-FLAG", "#{prefix}/bilingual", "#{subject} does not teach a language: bilingual: true is for english and spanish", rule: "flag-subject")
        return findings
      end
      return findings if lang.nil?

      Lessons::Lang.keyed(doc).each do |pointer, key, _text|
        sibling = Lessons::Lang.key_lang(key)
        next unless Lessons::Lang::PAIR_LANGS.include?(sibling)
        next if NOT_TEXT.include?(key.sub(/_(en|es)\z/, ""))

        message = if sibling != lang then "#{key} holds #{sibling == 'es' ? 'Spanish' : 'English'} text in a #{subject} revision (#{subject} teaches #{lang == 'es' ? 'Spanish' : 'English'}): use _#{lang}"
                  elsif !bilingual?(doc) then "#{key} is a target-language sibling in a revision without bilingual: true: add the marker, every text then has its translation"
                  end
        next unless message

        findings.add("E-LANG-BILINGUAL-FLAG", "#{prefix}#{pointer}", message, rule: "flag-#{prefix}#{pointer}", **(line ? { line: line.call(pointer) }.compact : {}))
      end
      findings
    end

    # E-LANG-BILINGUAL-REQUIRED: a new submission of a subject listed in lang.bilingual_required without the marker. A revision that passed
    # under older rules (+grandfathered+) keeps its pass.
    def required(findings, doc, subject:, grandfathered: false)
      return findings if grandfathered || bilingual?(doc) || !Rules.list(:lang, :bilingual_required).include?(subject.to_s)

      findings.add("E-LANG-BILINGUAL-REQUIRED", "/bilingual", "a new revision of #{subject} is bilingual: add bilingual: true and write every text in the language it teaches with its Italian translation", rule: "required")
    end

    # ---- the target-language lint ---------------------------------------------------------------------------------------------

    # The lint of every `_<lang>` text of +doc+ (the keys of the subject's language only): sentences of at most
    # lesson2.target_sentence_words words, the 60-word stem, and W-LANG-LEVEL (words outside the first 3000 of the language, the common given
    # names and +known+ aside).
    def lint_target(findings, doc, lang, known: [], prefix: "", line: nil)
      allowed = names(lang) | Array(known).to_set(&:to_s)
      Lessons::Lang.keyed(doc).each do |pointer, key, text|
        next unless Lessons::Lang.key_lang(key) == lang

        base = key.sub(/_#{lang}\z/, "")
        next if NOT_TEXT.include?(base)

        target_lint(findings, "#{prefix}#{pointer}", lang, text, known: allowed, line: line&.call(pointer), stem: base == "stem")
      end
      findings
    end

    def target_lint(findings, field, lang, text, known: [], line: nil, stem: false)
      at = line ? { line: line }.compact : {}
      name = lang == "es" ? "Spanish" : "English"
      max = Rules.get(:lesson2, :target_sentence_words)
      sentences = Readability.sentences_of(Readability.strip_markup(text.to_s.gsub(Readability::MATH, " m ")))
      long = sentences.map { |s| Readability.count_words(s) }.max.to_i
      findings.add("E-READ", field, "an #{name} sentence has #{long} words (at most #{max})", rule: "target_sentence_words-#{field}", words: long, **at) if long > max
      words = sentences.sum { |s| Readability.count_words(s) }
      if stem && words > Rules.get(:readability, :max_stem_words)
        findings.add("E-READ", field, "the instruction has #{words} words (at most #{Rules.get(:readability, :max_stem_words)})", rule: "stem_length-#{field}", words: words, **at)
      end
      unknown = Lessons::Lexicon.unknown(lang, text.to_s.gsub(/\[\[[a-z]+(?:[_-][a-z]+)*(?:\|it)?:(.*?)\]\](?!\])/m, '\1'), known: known)
      return if unknown.empty?

      findings.add("W-LANG-LEVEL", field, "#{name} words outside the first #{Rules.get(:lesson2, :target_vocabulary_top)} (and the given names, the glossary and teaches_#{lang}): #{unknown.first(6).join(', ')}", rule: "lang-level-#{field}", words: unknown, **at)
    end

    # The common given names of +lang+ (config/banco/lexicon/<lang>_names.txt), lower case: never words to teach.
    def names(lang)
      @names ||= {}
      @names[lang] ||= begin
        path = File.join(NAMES_DIR, "#{lang}_names.txt")
        (File.exist?(path) ? File.readlines(path, chomp: true) : []).map { |n| n.strip.downcase }.reject { |n| n.empty? || n.start_with?("#") }.to_set.freeze
      end
    end

    # ---- the layers -----------------------------------------------------------------------------------------------------------------

    # Runs a check written before D-402 on the two layers of a bilingual +doc+: the block gets the target layer, then the Italian layer, each with
    # its own Findings. What the target layer finds is added to +findings+ with the keys as the author wrote them (`steps_en`); what the Italian
    # layer finds is added with its own rule and a note, so a translation that gives the key away is told from the text that does.
    def layers(doc, lang, findings, seed: nil)
      renamed = Set.new
      target = target_layer(doc, lang, "", renamed)
      yield target, (found = Findings.new)
      found.each { |f| findings.add(f.code, author_pointer(f.field, lang, renamed), f.message, **f.detail.except(:seeds, :count), seed: f.detail[:seeds]&.first || seed) }
      yield Lessons::Bilingual.italian_layer(doc), (italian = Findings.new)
      italian.each do |f|
        findings.add(f.code, f.field, "in the Italian translation: #{f.message}", **f.detail.except(:seeds, :count), rule: "it-#{f.detail[:rule]}", seed: f.detail[:seeds]&.first || seed)
      end
    end

    # +doc+ as the checks written before D-402 read it: every target text sits under its legacy `_it` key (`stem_en` becomes `stem_it`) and the
    # Italian translations are gone (`text_it`, `final_it`, `header_it`, ... of rule R2 too). Paired fields only; a text with no translation is
    # renamed all the same, an Italian text with no target stays. Findings made on this layer name the keys of the legacy shape: `renamed` lists
    # the bases that were renamed (see +author_pointer+).
    def target_layer(doc, lang = nil, pointer = "", renamed = nil)
      case doc
      when Hash
        out = doc.dup
        Lessons::Bilingual.twins(doc, lang, pointer).each do |base, tkey, ikey, kind|
          next if tkey.nil? || kind == :legacy

          if kind == :r2
            out.delete(ikey)
          else
            out.delete(ikey)
            out.delete(tkey)
            out["#{base}_it"] = doc[tkey]
            renamed&.add(base)
          end
        end
        out.to_h { |k, v| [ k, v.is_a?(Hash) || v.is_a?(Array) ? target_layer(v, lang, "#{pointer}/#{k}", renamed) : v ] }
      when Array then doc.each_with_index.map { |v, i| v.is_a?(Hash) || v.is_a?(Array) ? target_layer(v, lang, "#{pointer}/#{i}", renamed) : v }
      else doc
      end
    end

    # A finding field made on the target layer, with its keys as the author wrote them: `/display/stem_it` -> `/display/stem_en`.
    def author_pointer(field, lang, renamed)
      field.to_s.gsub(%r{(?<=/)([a-z_]+)_it(?=/|\z)}) { renamed.include?(Regexp.last_match(1)) ? "#{Regexp.last_match(1)}_#{lang}" : Regexp.last_match(0) }
    end
  end
end
