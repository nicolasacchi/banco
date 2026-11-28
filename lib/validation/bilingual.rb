# frozen_string_literal: true

module Validation
  # The checks of the bilingual courses of english and spanish (D-402, §4.2), shared by the item, lesson, course, graph and topic checks.
  # A bilingual revision writes every student text twice: the target language under `<base>_en|_es` and its Italian under `<base>_it`.
  # `Lessons::Bilingual.pairs` walks the pairs; this module decides what is wrong with each:
  #
  #   E-LANG-PAIR-MISSING / -ORPHAN   a text without its translation, a translation without its text, lists of different length
  #   E-LANG-PAIR-SHAPE               paragraphs, list items, ___ blanks, math, digits, bold words, [[g:..]] terms differ
  #   E-LANG-PAIR-CONFLICT            two equal target strings in one scope with different Italian (W-LANG-PAIR-CONFLICT when the text is a label of 3 words or fewer, or when one of the two is a `final`)
  #   E-LANG-TRANSLATION-LANG         an `_it` text that is not Italian; E-LESSON-LANG for a `_en|_es` text that is Italian
  #   E-LANG-TRANSLATION-COPY         an `_it` text equal to its target text
  #   E-LANG-BILINGUAL-FLAG / -REQUIRED   the `bilingual` marker (flag) and the rule that asks for it (required)
  #
  # plus the lint of the target-language texts (12-word sentences, the 60-word stem, W-LANG-LEVEL with the given names allowed, the form material read for the level
  # too) and the target layer of a document: the document with each target text under its legacy `_it` key, which the checks written before D-402 read.
  module Bilingual
    # Bases whose `_en` key is not a translated text (a vocabulary list the lesson teaches).
    NOT_TEXT = (Lessons::Bilingual::FIELDS[:target_only] + Lessons::Bilingual::FIELDS[:native] + Lessons::Bilingual::EXEMPT).freeze
    SPAN = /\[\[(?:en|es|la|code):.*?\]\](?!\])/m
    # The spans of another language and the code spans, Italian ones included: words quoted, not said (never a word of the level).
    QUOTED_SPAN = /\[\[(?:en|es|la|it|code):.*?\]\](?!\])/m
    QUOTED = /«[^»]*»|"[^"]*"|“[^”]*”/
    LIST_ITEM = /^[ \t]*(?:[-*]|\d+[.)])[ \t]+/
    DIGITS = /\d[\d.,]*/
    NAMES_DIR = Lessons::Lexicon::DIR

    module_function

    def bilingual?(doc) = doc.is_a?(Hash) && doc["bilingual"] == true

    # ---- the walk -------------------------------------------------------------------------------------------------------------

    # Adds the findings of every pair of +doc+ (a body, a block, an item, a front matter) to +findings+. +lang+ is the subject's language;
    # +prefix+ goes before each pointer; +line+ (a pointer -> Integer or nil) puts a line in the detail; +skip+ (pointer, base -> true) leaves a pair
    # to the caller; +conflicts+ is off for an item (its instances are not one translation table); +material+: the marker `translate_material: false` is in force
    # above +doc+ (an instance is checked on its own, the item's root says it): form material has no pair, and an Italian text beside it is E-LANG-PAIR-ORPHAN.
    # Returns +findings+.
    # +example_forms+ (a course map's topics): the `title_it` that lists example forms after a colon («La forma passiva: fue escrito por, está escrito») is read before the colon.
    def check(findings, doc, lang:, prefix: "", line: nil, skip: nil, conflicts: true, r2: true, material: false, known: [], example_forms: false)
      table = {}
      Lessons::Bilingual.pairs(doc, lang, "", false, material) do |pointer, base, target, italian|
        next if skip&.call(pointer, base)
        next unless (target.nil? || target.is_a?(String)) && (italian.nil? || italian.is_a?(String))

        field = "#{prefix}#{pointer}"
        at = line ? { line: line.call(pointer) }.compact : {}
        target = nil if target.to_s.strip.empty?
        italian = nil if italian.to_s.strip.empty?
        pair_lang = lang || pointer[/_(en|es)(?:\/\d+)*\z/, 1]
        add = ->(code, message, where = field) { findings.add(code, where, message, rule: "#{code}-#{where}", **at) }
        # The names of the two fields in the messages: the target's own key (`stem_en`, `final`, `text`) and `<base>_it`; an R2 key is its own target.
        names = field_names(pointer, base)

        if target.nil? && italian.nil?
          next
        elsif italian.nil?
          add.call("E-LANG-PAIR-MISSING", "#{names[0]} has its #{pair_lang || 'target-language'} text but no Italian translation (#{names[1]})")
        elsif target.nil?
          add.call(pointer.match?(%r{/\d+\z}) ? "E-LANG-PAIR-MISSING" : "E-LANG-PAIR-ORPHAN",
                   pointer.match?(%r{/\d+\z}) ? "#{names[1]} has more entries than #{names[0]} (a list and its translation have the same length)" : "#{names[1]} has no #{names[0]} text to translate")
        else
          it_field = "#{prefix}#{italian_pointer(pointer, base)}"
          shape_problems(target, italian).each { |problem| add.call("E-LANG-PAIR-SHAPE", "#{base}: the translation differs in shape: #{problem}") }
          add.call("E-LESSON-LANG", "#{names[0]} holds Italian words (a key ending in _#{pair_lang} holds that language only)") if %w[en es].include?(pair_lang) && Lessons::Lang.italian?(target)
          add.call("E-LANG-TRANSLATION-LANG", "#{names[1]} is not Italian: it holds words of #{pair_lang == 'es' ? 'Spanish' : 'English'}", it_field) if translation_lang?(italian, pair_lang, example_forms: example_forms && base == "title")
          add.call("E-LANG-TRANSLATION-COPY", "#{names[1]} is the same text as #{names[0]}: write the translation", it_field) if base != "term" && copy?(target, italian, pair_lang, known: known)
          conflict(findings, table, field, target, italian, at) if conflicts
        end
      end
      Lessons::Bilingual.material_fields(doc, lang, "", false, material) do |pointer, base, tkey, ikey|
        next unless ikey

        field = "#{prefix}#{pointer}/#{ikey}"
        next if skip&.call("#{pointer}/#{ikey}", base)

        message = if tkey then "#{ikey} translates form material: a form of the exercise (the sentence with its blank, an option, a row, the final, a mistake's wrong and right) is target-only, delete #{ikey}"
        else "#{ikey} is a form of the exercise: form material is written in the target language only (#{base}_#{lang || 'en'} or the bare key), with no Italian text"
        end
        findings.add("E-LANG-PAIR-ORPHAN", field, message, rule: "E-LANG-PAIR-ORPHAN-#{field}", **(line ? { line: line.call("#{pointer}/#{ikey}") }.compact : {}))
      end
      r2_gaps(doc, "", material) do |pointer, base|
        next if skip&.call(pointer, base)

        findings.add("E-LANG-PAIR-MISSING", "#{prefix}#{pointer}", "#{base} has no Italian translation (#{base}_it beside it)", rule: "E-LANG-PAIR-MISSING-#{prefix}#{pointer}", **(line ? { line: line.call(pointer) }.compact : {}))
      end if r2
      findings
    end

    # [the target field's own key, the Italian key] of the pair at +pointer+: `final` and `final_it`, `stem_en` and `stem_it`; a list entry names its list.
    def field_names(pointer, base)
      key = pointer.split("/").reject { |s| s.match?(/\A\d+\z/) }.last.to_s
      [ key, "#{base}_it" ]
    end

    # The pointer of the Italian field beside the target field at +pointer+ (`/instances/0/solution/final` -> `.../final_it`, `.../hints_en/1` -> `.../hints_it/1`).
    # A flow's edge label (`.../edges/1/2`) has its Italian at `.../edges_it/1`.
    def italian_pointer(pointer, base)
      return pointer.sub(%r{/edges/(\d+)/2\z}, '/edges_it/\1') if base == "edges"

      pointer.sub(%r{[^/]+((?:/\d+)*)\z}) { "#{base}_it#{Regexp.last_match(1)}" }
    end

    # The fields of rule R2 (an option's `text`, a table's `header` and `rows`, `quote.text`, a solution's `final`) hold the target text under the bare
    # key: `Lessons::Bilingual.pairs` meets them only through their `_it` twin, so a bare key with no twin is found here: yields (pointer, base). Form
    # material (+material+: the marker is in force above) has no twin by design.
    def r2_gaps(node, pointer = "", material = false, &block)
      case node
      when Hash
        material = Lessons::Bilingual.material_in?(node, material)
        Lessons::Bilingual::FIELDS[:r2].each_key do |base|
          value = node[base]
          next unless Lessons::Bilingual.r2?(node, base, pointer) && !node.key?("#{base}_it") && (value.is_a?(String) ? !value.strip.empty? : value.is_a?(Array) && value.any?)
          next if Lessons::Bilingual.material?(node, base, pointer, material)

          yield "#{pointer}/#{base}", base
        end
        node.each { |k, v| r2_gaps(v, "#{pointer}/#{k}", material, &block) if v.is_a?(Hash) || v.is_a?(Array) }
      when Array then node.each_with_index { |v, i| r2_gaps(v, "#{pointer}/#{i}", material, &block) if v.is_a?(Hash) || v.is_a?(Array) }
      end
    end

    SHORT_LABEL_WORDS = 3
    # The target text of a step is often the `final` of its exercise, with a shorter or longer Italian: «Does Jack study German?» is both. Reading them as two translations of one text is a warning.
    FINAL_FIELD = %r{/final(?:_(?:en|es))?(?:/\d+)?\z}

    def conflict(findings, table, field, target, italian, at)
      key = plain(target)
      first = table[key]
      if first.nil?
        table[key] = [ italian, field ]
      elsif !same_italian?(first[0], italian)
        short = key.scan(Readability::WORD).size <= SHORT_LABEL_WORDS || [ field, first[1] ].any? { |f| FINAL_FIELD.match?(f) } # a label of a few words (a state, a verb form) reads differently in two places, and a final is repeated by a step: only the first translation is shown
        findings.add(short ? "W-LANG-PAIR-CONFLICT" : "E-LANG-PAIR-CONFLICT", field, "the same text has another translation at #{first[1]}: the translation table is keyed by the target text, so write one Italian for it", rule: "conflict-#{field}", **at)
      end
    end

    # Two Italian texts are the same translation when they have the same words: a full stop, a capital letter or markup does not make another translation.
    def same_italian?(one, other) = plain(one).scan(Readability::WORD) == plain(other).scan(Readability::WORD)

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
      out << "the numbers differ (#{surplus(digits[0], digits[1]).first(3).join(', ')} / #{surplus(digits[1], digits[0]).first(3).join(', ')})" if digits[0].sort != digits[1].sort
      out
    end

    def paragraphs(text) = text.split(/\n[ \t]*\n/).count { |p| !p.strip.empty? }

    def math_of(text) = text.scan(Readability::MATH).map { |m| m.gsub(/\s+/, "") }

    # Digit runs outside math, without the thousands and decimal marks (3.5 and 3,5, 1,000 and 1.000 read the same).
    # A clock time is one number: «9:30» in English and «9.30» or «9:30» in Italian read «930»; the hours and the minutes are not two numbers.
    CLOCK = /(?<![\d:.,])(\d{1,2})[:.](\d{2})(?![\d,]|[:.]\d)/

    def digits_of(text) = text.gsub(Readability::MATH, " ").gsub(CLOCK, ' \1\2 ').scan(DIGITS).map { |d| d.delete(".,") }.reject(&:empty?)

    # The elements of +a+ that +b+ does not have as many times (a number said twice in one text and once in the other differs).
    def surplus(a, b)
      left = b.tally
      a.reject { |d| left[d].to_i.positive? && left[d] -= 1 }
    end

    # ---- the language of the two texts ------------------------------------------------------------------------------------------

    # The words of +text+ the way the language checks read them: markup and spans reduced to their words, math dropped, lower case.
    def plain(text)
      text.to_s.gsub(Readability::MATH, " ")
          .gsub(/\[\[code:.*?\]\](?!\])/m, " ")
          .gsub(/\[\[(?:[a-z]+(?:[_-][a-z]+)*)(?:\|it)?:(.*?)\]\](?!\])/m, '\1')
          .gsub(/\[([^\[\]]*)\]\((?:scheda|argomento):[^()]*\)/, '\1')
          .delete("*_").downcase.gsub(/[[:space:]]+/, " ").strip
    end

    # A role span of a language subject's text holds a target-language form («[[od:lo]]», «[[oi:le]]») unless it says |it, so in an Italian text it is quoted target,
    # like a span of a language.
    ROLE_SPAN = /\[\[(?!g:)[a-z]+(?:[_-][a-z]+)*:.*?\]\](?!\])/m

    # True when an Italian text holds two distinct function words of the target language outside spans and quotations (a translation that was
    # not translated). +lang+ nil reads both lists. +example_forms+: a title of the shape «Name: form, form» is read up to its colon when what follows is a list of short
    # forms (at most EXAMPLE_FORM_WORDS words each): the forms are target text on purpose. A title that is a sentence is read whole.
    def translation_lang?(italian, lang, example_forms: false)
      text = italian.to_s
      text = text.split(":", 2).first if example_forms && example_forms?(text)
      outside = text.gsub(QUOTED_SPAN, " ").gsub(ROLE_SPAN, " ").gsub(QUOTED, " ").gsub(Readability::MATH, " ")
      words = outside.downcase.scan(/\p{L}+/)
      lists = lang ? [ Lessons::Lang::TARGET_WORDS.fetch(lang, []) ] : Lessons::Lang::TARGET_WORDS.values
      lists.any? { |list| (words & list).size >= 2 }
    end

    EXAMPLE_FORM_WORDS = 4

    def example_forms?(text)
      before, after = text.split(":", 2)
      return false if after.to_s.strip.empty? || before.to_s.strip.empty?

      after.split(/[,;]/).all? { |form| form.scan(/\p{L}+/).size.between?(1, EXAMPLE_FORM_WORDS) }
    end

    # True when the Italian is the target text itself (after spans and markup) and BOTH hold a word of four or more letters that is not quoted: a text that is all
    # [[en:..]] / [[es:..]] spans or «...»-quoted forms (a form is the same in both languages), in either language, is no copy; nor is a text whose only other words
    # are shared connectors («con», «a», «e») or pieces of words. The Italian one is read too: «[[es:hacer]]: [[es:hago]]» beside «hacer: hago» quotes its forms on purpose.
    # A label of three words or fewer with nothing in it that Italian lacks («Una cosa» beside «una cosa») is one word of the two languages, no copy (+shared_label?+).
    def copy?(target, italian, lang = nil, known: [])
      plain(target) == plain(italian) && [ target, italian ].all? { |text| own_words?(text) } && !shared_label?(target, lang) && !shared_text?(target, lang, known)
    end

    SHARED_TEXT_WORDS = 6

    # A short text whose every word is a word of the language that Italian shares («Haber cambia con la persona», «La tilde»): the same in both languages, no copy.
    # No word that is outside the easy words of the language and its +known+ words (the glossary, teaches_<lang>), no letter or digraph Italian lacks (FOREIGN), no
    # function word of the language that Italian lacks (TARGET_WORDS), at most SHARED_TEXT_WORDS words. A text of a language that is not known (+lang+ nil) is never one.
    def shared_text?(text, lang, known = [])
      return false unless lang && Lessons::Lexicon::LANGS.include?(lang)

      plain = plain(text)
      words = plain.scan(Readability::WORD)
      return false if words.empty? || words.size > SHARED_TEXT_WORDS || plain.match?(FOREIGN)
      return false if (words & Lessons::Lang::TARGET_WORDS.fetch(lang, [])).any?

      known = known.to_set
      words.all? { |w| known.include?(w) || Lessons::Lexicon.known?(lang, w) }
    end

    # Letters and digraphs that Italian does not use (j k w x y ñ ¿ ¡ á í ú ü, th sh ck ee oo ou, -ing): a label with one of them, or with a function word of the language
    # that Italian lacks (TARGET_WORDS), is not the same word in the two languages.
    FOREIGN = /[jkwxyñ¿¡áíúü]|th|sh|ck|ee|oo|ou|ing\b/i

    def shared_label?(text, lang)
      words = plain(text).scan(Readability::WORD)
      return false if words.empty? || words.size > SHORT_LABEL_WORDS || plain(text).match?(FOREIGN)

      lists = lang ? [ Lessons::Lang::TARGET_WORDS.fetch(lang, []) ] : Lessons::Lang::TARGET_WORDS.values
      lists.none? { |list| (words & list).any? }
    end

    # Does +text+ hold a word of four letters outside its spans, quotations, formulas and pieces of words?
    def own_words?(text)
      plain(text.to_s.gsub(QUOTED_SPAN, " ").gsub(QUOTED, " ").gsub(PIECES, " ")).match?(/\p{L}{4,}/)
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

      if !bilingual?(doc) && (marker = marker_pointers(doc)).any?
        marker.each { |pointer| findings.add("E-LANG-BILINGUAL-FLAG", "#{prefix}#{pointer}", "#{Lessons::Bilingual::MARKER} is for a bilingual revision (it says that the form material has no translation): add bilingual: true", rule: "flag-material-#{prefix}#{pointer}") }
      end

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

    # The pointers of the `translate_material` keys under +node+.
    def marker_pointers(node, pointer = "")
      case node
      when Hash then node.flat_map { |k, v| (k == Lessons::Bilingual::MARKER ? [ "#{pointer}/#{k}" ] : []) + marker_pointers(v, "#{pointer}/#{k}") }
      when Array then node.each_with_index.flat_map { |v, i| marker_pointers(v, "#{pointer}/#{i}") }
      else []
      end
    end

    # ---- the target-language lint ---------------------------------------------------------------------------------------------

    # The lint of every `_<lang>` text of +doc+ (the keys of the subject's language only): sentences of at most
    # lesson2.target_sentence_words words, the 60-word stem, and W-LANG-LEVEL and W-ABSOLUTE (words outside the first 3000 of the language, the common given
    # names and +known+ aside). +material+: the marker is in force above +doc+. The form material of an exercise (the sentence with its blank, an option, a row,
    # which have no Italian beside them) is read for the level too, as the student reads it in the target language alone: the words of the item's own keys,
    # accepted answers and error values are the forms it teaches and never a level word (+own_words+); it has no W-ABSOLUTE (it is the exercise's material).
    def lint_target(findings, doc, lang, known: [], prefix: "", line: nil, material: false)
      allowed = names(lang) | Array(known).to_set(&:to_s)
      forms = Lessons::Bilingual.material_pointers(doc, lang, material)
      Lessons::Lang.keyed(doc).each do |pointer, key, text|
        next unless Lessons::Lang.key_lang(key) == lang

        base = key.sub(/_#{lang}\z/, "")
        next if NOT_TEXT.include?(base)

        form = forms.include?(pointer)
        target_lint(findings, "#{prefix}#{pointer}", lang, text, known: form ? allowed | own_words(doc, pointer, lang) : allowed, line: line&.call(pointer), stem: base == "stem", absolute: !form)
      end
      bare_material(doc, lang, "", material) do |pointer, text|
        target_lint(findings, "#{prefix}#{pointer}", lang, text, known: allowed | own_words(doc, pointer, lang), line: line&.call(pointer), absolute: false, cap: false)
      end
      findings
    end

    # +absolute+ false: no W-ABSOLUTE; +cap+ false: no sentence cap (a cell of a table is a form, not a sentence).
    def target_lint(findings, field, lang, text, known: [], line: nil, stem: false, absolute: true, cap: true)
      at = line ? { line: line }.compact : {}
      name = lang == "es" ? "Spanish" : "English"
      max = Rules.get(:lesson2, :target_sentence_words)
      report = target_report(lang, text, known: known, absolute: absolute)
      findings.add("E-READ", field, "an #{name} sentence has #{report[:long]} words (at most #{max})", rule: "target_sentence_words-#{field}", words: report[:long], **at) if cap && report[:long] > max
      if cap && stem && report[:words] > Rules.get(:readability, :max_stem_words)
        findings.add("E-READ", field, "the instruction has #{report[:words]} words (at most #{Rules.get(:readability, :max_stem_words)})", rule: "stem_length-#{field}", words: report[:words], **at)
      end
      findings.add("W-ABSOLUTE", field, "an absolute word (#{report[:absolute]}) needs a counterexample check", rule: "absolute-#{field}", word: report[:absolute], **at) if report[:absolute]
      return if report[:unknown].empty?

      findings.add("W-LANG-LEVEL", field, "#{name} words outside the first #{Rules.get(:lesson2, :target_vocabulary_top)} (and the given names, the glossary and teaches_#{lang}): #{report[:unknown].first(6).join(', ')}", rule: "lang-level-#{field}", words: report[:unknown], **at)
    end

    # ---- the level of form material ---------------------------------------------------------------------------------------------

    OPTION_LISTS = %w[options elements left right tiles items].freeze

    # The bare target text of form material (rule R2: an option's `text`, the `header` and the `rows` of a table, which have no `_<lang>` key to be found by):
    # yields (pointer of the text, text); a table's cells one by one. +material+: the marker is in force above +node+.
    def bare_material(node, lang, pointer = "", material = false, &block)
      case node
      when Hash
        material = Lessons::Bilingual.material_in?(node, material)
        %w[text header rows].each do |base|
          value = node[base]
          next unless value && Lessons::Bilingual.r2?(node, base, pointer) && Lessons::Bilingual.material?(node, base, pointer, material)

          cells(value, "#{pointer}/#{base}", &block)
        end
        node.each { |k, v| bare_material(v, lang, "#{pointer}/#{k}", material, &block) if v.is_a?(Hash) || v.is_a?(Array) }
      when Array then node.each_with_index { |v, i| bare_material(v, lang, "#{pointer}/#{i}", material, &block) if v.is_a?(Hash) || v.is_a?(Array) }
      end
    end

    def cells(value, pointer, &block)
      if value.is_a?(Array) then value.each_with_index { |v, i| cells(v, "#{pointer}/#{i}", &block) }
      elsif value.is_a?(String) then yield pointer, value
      end
    end

    # The lower-case words that ARE the forms taught at +pointer+ of +doc+ (an item, a lesson body): the key, the accepted answers and the error values of the
    # item, instance or check that holds the field, and the text of the options they name by id. They are in the material on purpose.
    def own_words(doc, pointer, lang)
      words = Set.new
      node = doc
      holders = [ doc ]
      pointer.to_s.split("/").reject(&:empty?).each do |segment|
        node = node.is_a?(Array) ? node[segment.to_i] : (node.is_a?(Hash) ? node[segment] : nil)
        break unless node.is_a?(Hash) || node.is_a?(Array)

        holders << node
      end
      holders.each { |holder| key_words(holder, lang, words) if holder.is_a?(Hash) }
      words
    end

    def key_words(hash, lang, words)
      key_words(hash["check"], lang, words) if hash["check"].is_a?(Hash)
      return unless %w[answer accept errors].any? { |k| hash.key?(k) }

      options = [ hash, hash["display"] ].select { |h| h.is_a?(Hash) }.flat_map { |h| OPTION_LISTS.flat_map { |k| Array(h[k]) } }.grep(Hash)
      texts = options.to_h { |o| [ o["id"].to_s, o["text"] || o["text_#{lang}"] ] }
      errors = Array(hash["errors"]).grep(Hash).flat_map { |e| [ e["answer"], e["value"] ] }
      values = [ hash["answer"], hash["accept"], *errors ].flatten.flat_map { |v| v.is_a?(Hash) ? v.to_a.flatten : [ v ] }.grep(String)
      values.each { |v| words.merge([ v, texts[v] ].compact.flat_map { |t| t.downcase.tr("’", "'").scan(Lessons::Lexicon::WORD) }) }
    end

    MARKUP_SPAN = /\[\[(?:[a-z]+(?:[_-][a-z]+)*)(?:\|it)?:(.*?)\]\](?!\])/m
    LINK = /\[([^\[\]]*)\]\((?:scheda|argomento):[^()]*\)/
    # The pieces of a word and the ending quoted bare, «ja-mon», «-es»: the exercise's material, never a word of the level.
    PIECES = /\p{L}+-[\p{L}-]*|-\p{L}[\p{L}-]*/
    # Abbreviations whose full stop does not end the sentence. Any other letter or word followed by a full stop and a space does.
    ABBREVIATIONS = /(?<![\p{L}])(?:Mr|Mrs|Ms|Dr|Prof|St|Sr|Sra|Srta|Sres|Dña|vs|etc)\./
    # What the target-language lint reads of a text: the longest sentence in words, all the words (the instruction's length), the words outside the level
    # and the absolute word, if any: {long:, words:, unknown:, absolute:}. +level+ false: no unknown word, no absolute one; +absolute+ false: no absolute
    # one (the words of the exercise's material: a sentence, an option, the text around a box).
    def target_report(lang, text, known: [], level: true, absolute: true)
      counts = target_sentences(sentence_text(text)).map { |s| Readability.count_words(s) }
      out = { long: counts.max.to_i, words: counts.sum, unknown: [], absolute: nil }
      return out unless level

      read = level_text(text)
      out[:unknown] = Lessons::Lexicon.unknown(lang, read, known: known)
      out[:absolute] = absolute_word(lang, read) if absolute
      out
    end

    # A colon that follows a closing quote («...»:), or one followed by a quote, a capital letter, a span or an opening ¿ or ¡, ends a sentence like a semicolon does.
    # (A lesson's text reaches this with its spans already read as ` m `, the one word they count.)
    COLON_BREAK = /(?<=[»”"])\s*:\s*|\s*:\s*(?=[¿¡])|\s*:\s+(?=\[\[|[«“"]|\p{Lu}|m\s)/
    # An Italian or code span counts one word; when its own full stop closes it (`[[it:Che bello!]]`) the stop still ends the sentence, as a quotation's does.
    SPAN_ONE_WORD = /\[\[(?:it|code):(.*?)\]\](?!\])/m

    # The text of a target-language field as the sentence cap reads it: a formula and an Italian or code span count one word, a quotation («...», “...”: the forms
    # and sentences the text talks about) and a piece of a word (-es, ja-mon) none, other markup shows its words; a colon of COLON_BREAK splits.
    def sentence_text(text)
      text = text.to_s.gsub(COLON_BREAK, "; ")
      one_word = text.gsub(Readability::MATH, " m ").gsub(SPAN_ONE_WORD) { Regexp.last_match(1).match?(/[.!?…]\s*\z/) ? " m . " : " m " }
      Readability.strip_markup(Readability.without_quotations(one_word).gsub(MARKUP_SPAN, '\1').gsub(LINK, '\1').gsub(PIECES, " "))
    end

    # ... as the level lint reads it: no formula, no span of a language, no quoted form («jámon»), no piece of a word (ja-mon, -es); other markup shows its words.
    def level_text(text)
      text.to_s.gsub(Readability::MATH, " ").gsub(QUOTED_SPAN, " ").gsub(QUOTED, " ").gsub(MARKUP_SPAN, '\1').gsub(LINK, '\1').gsub(PIECES, " ")
    end

    MERIDIEM = /\A[ap]\.m\.\z/i

    # The sentences of a target-language text: a full stop (or ? or !) followed by a space ends one, also after a letter («acaba en n. Lleva») and inside a
    # closing quote (`.»`, `?»`, `!»`); a semicolon splits; a line ends one. Only the titles and a dotted abbreviation (a.m.) keep their stop.
    def target_sentences(text)
      protected = text.gsub(ABBREVIATIONS) { |m| m.tr(".", "\u0001") }.gsub(Readability::DOTTED) do |m|
        # a.m. and p.m. close a sentence when a capital follows, as a.C. and d.C. do (Readability::ERAS); any other dotted abbreviation (e.g., i.e.) never does
        m.match?(MERIDIEM) && Regexp.last_match.post_match.match?(/\A\s+\p{Lu}/) ? m : m.tr(".", "\u0001")
      end
      protected.split(/(?<=[.!?…][»”"])\s+|(?<=[.!?…])\s+|;\s*|\n+/).map { |s| s.tr("\u0001", ".").strip }.reject { |s| s.scan(Readability::WORD).empty? }
    end

    # The first absolute word of the language (config/banco/validation_rules.yml readability.absolute_words_target: never «only» or «solo», the word of the
    # instruction «Write only the missing words»).
    def absolute_word(lang, text)
      words = Array(Rules.get(:readability, :absolute_words_target)[lang])
      lower = text.downcase
      words.find { |w| lower.match?(/(?<!\p{L})#{Regexp.escape(w)}(?!\p{L})/) }
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
    def target_layer(doc, lang = nil, pointer = "", renamed = nil, sentence = false, material = false)
      case doc
      when Hash
        out = doc.dup
        sentence = Lessons::Bilingual.in_sentence?(doc, sentence)
        material = Lessons::Bilingual.material_in?(doc, material)
        Lessons::Bilingual.twins(doc, lang, pointer, sentence: sentence, material: material).each do |base, tkey, ikey, kind|
          next if tkey.nil? || kind == :legacy

          if tkey == base # an R2 key: the bare key is the target text already
            out.delete(ikey)
          else
            out.delete(ikey)
            out.delete(tkey)
            out["#{base}_it"] = doc[tkey]
            renamed&.add(base)
          end
        end
        out.to_h { |k, v| [ k, v.is_a?(Hash) || v.is_a?(Array) ? target_layer(v, lang, "#{pointer}/#{k}", renamed, sentence, material) : v ] }
      when Array then doc.each_with_index.map { |v, i| v.is_a?(Hash) || v.is_a?(Array) ? target_layer(v, lang, "#{pointer}/#{i}", renamed, sentence, material) : v }
      else doc
      end
    end

    # A finding field made on the target layer, with its keys as the author wrote them: `/display/stem_it` -> `/display/stem_en`.
    def author_pointer(field, lang, renamed)
      field.to_s.gsub(%r{(?<=/)([a-z_]+)_it(?=/|\z)}) { renamed.include?(Regexp.last_match(1)) ? "#{Regexp.last_match(1)}_#{lang}" : Regexp.last_match(0) }
    end
  end
end
