# frozen_string_literal: true

module Lessons
  # The bilingual courses of english and spanish (D-402). A revision with `bilingual: true` writes every student text twice: the target
  # language under `<base>_en|_es` and its Italian translation under `<base>_it` (rule R1). A few item keys have no suffix and already hold the
  # subject's language: they keep it and the Italian goes to `<key>_it` (rule R2). This module is the one place that knows which fields pair:
  #
  #   Bilingual.pairs(doc, lang)    yields (pointer, base, target, italian) for every text of a document, to the validators
  #   Bilingual.fold(served, lang)  a served lesson with the target in the renderer's `_it` slots and the Italian in block-scoped `tr` tables
  #   Bilingual.italian_layer(doc)  the document as the student reads it with the translation open, for the answer-leak scans
  #
  # Pure Ruby, no database. Default is "student-facing means paired": a field leaves the rule only by being listed in EXEMPT.
  module Bilingual
    # Keys (their base, without `_it`) that are never paired: the teacher's own words, what points at the Italian textbook, what is graded or
    # typed by a program. `rubric.points[].expected_it` and the short answer's `model_answer_it` follow Q5 of D-402: the rubric stays Italian, the
    # model answer is a pair like any other text (`model_answer_en` is the English one).
    EXEMPT = %w[description choice_only_reason notes reachable_ok book reason scope_reason expected input].freeze

    FIELDS = {
      # R2: bare item keys that hold the subject's language. Base => the pointer of the hash that holds it (the key's twin is `<base>_it`).
      r2: {
        "text" => %r{/(?:options|elements|left|right)/\d+\z|/quote\z},
        "header" => %r{/table\z},
        "rows" => %r{/table\z},
        "final" => %r{/solution\z}
      }.freeze,
      # Pairs that a figure or a block already draws by its own shape, as (Italian base => target base): a dialogue line's `text_en` and
      # `gloss_it`, a word_parts word's `form_en` and `label_it`. They count as pairs for the validators and are never folded.
      legacy: { "gloss" => "text", "label" => "form" }.freeze,
      # Both sides are drawn side by side by the figure itself (mirror: `pieces_it` and `pieces_en`): never folded, never an orphan.
      native: %w[pieces].freeze,
      # Target-language data with no Italian twin by design (vocabulary lists, forms, the `teaches_en` lexicon): never an orphan.
      target_only: %w[teaches form base past participle verb cells].freeze
    }.freeze

    # The levels of a served lesson that own a `tr` table: the body, each card, each block of a card.
    SCOPES = { "cards" => :body, "blocks" => :card }.freeze

    module_function

    # Every pair of +doc+ (a body, a front matter, an item, a figure, a course or a skill graph) as (pointer, base, target, italian):
    # the pointer is the target field's (where it would be when missing), +target+ or +italian+ is nil when that side is missing. A list
    # pairs by index (a missing or extra item is a nil side), a table row by row. +lang+ is the subject's language, nil for any of them.
    # Orphans come out too (a target without its Italian, an Italian without its target); the validators decide what each means.
    def pairs(node, lang = nil, pointer = "", &block)
      return enum_for(:pairs, node, lang, pointer) unless block

      case node
      when Hash
        twins(node, lang, pointer).each { |base, tkey, ikey, _| leaves("#{pointer}/#{tkey || "#{base}_#{lang || Lang.sibling_lang(node, base) || Lang::PAIR_LANGS.first}"}", base, tkey && node[tkey], ikey && node[ikey], &block) }
        node.each { |k, v| pairs(v, lang, "#{pointer}/#{k}", &block) if v.is_a?(Hash) || v.is_a?(Array) }
      when Array
        node.each_with_index { |v, i| pairs(v, lang, "#{pointer}/#{i}", &block) if v.is_a?(Hash) || v.is_a?(Array) }
      end
    end

    # The Italian layer of +doc+ (§4.2 rule 5): each pair is replaced by its Italian, so a scan for the key finds what the student reads
    # with the translation open. R1 keys keep `<base>_it` and lose the target sibling; R2 keys take the Italian in the bare key. Orphans,
    # legacy and native pairs stay as they are. A new object; +doc+ is not changed.
    def italian_layer(doc, pointer = "")
      case doc
      when Hash
        out = doc.dup
        twins(doc, nil, pointer).each do |base, tkey, ikey, kind|
          next if kind == :legacy || tkey.nil? || ikey.nil?

          if kind == :r2
            out[base] = doc[ikey]
            out.delete(ikey)
          else out.delete(tkey)
          end
        end
        out.to_h { |k, v| [ k, v.is_a?(Hash) || v.is_a?(Array) ? italian_layer(v, "#{pointer}/#{k}") : v ] }
      when Array then doc.each_with_index.map { |v, i| v.is_a?(Hash) || v.is_a?(Array) ? italian_layer(v, "#{pointer}/#{i}") : v }
      else doc
      end
    end

    # A served lesson body (the StudentBody whitelist's projection of a bilingual one) in the shape the renderer already reads (§2.5):
    # each R1 pair `foo_<lang>` + `foo_it` becomes `foo_it` holding the TARGET text, and the Italian goes to `tr`, a table {target string =>
    # Italian} on the nearest scope (the body, a card, a block of a card). The root gains `lang`. A list pairs by index. Fields without a
    # pair, legacy pairs (dialogue) and native pairs (mirror) are left as served. Two equal target strings in one scope keep the first Italian
    # (the validator refuses the conflict, E-LANG-PAIR-CONFLICT). A new object; +served+ is not changed.
    def fold(served, lang)
      { "lang" => lang }.merge(fold_scope(served, lang, :body))
    end

    # ---- walking ------------------------------------------------------------------------------------------------------------

    # The pairs of one hash as [[base, target_key, italian_key, kind]]; a side that is missing is nil; kind is :r1, :r2 or :legacy.
    def twins(hash, lang, pointer, r2: true)
      langs = lang ? [ lang ] : Lang::PAIR_LANGS
      out = []
      taken = []
      hash.each_key do |key|
        next unless key.is_a?(String) && (base = key[/\A(.+)_it\z/, 1])
        next if EXEMPT.include?(base) || FIELDS[:native].include?(base)

        tkey = langs.map { |l| "#{base}_#{l}" }.find { |k| hash.key?(k) }
        kind = :r1
        if tkey.nil? && r2 && hash.key?(base) && FIELDS[:r2][base]&.match?(pointer)
          tkey = base
          kind = :r2
        end
        if tkey.nil? && (target_base = FIELDS[:legacy][base]) && !hash.key?("#{target_base}_it")
          if (found = langs.map { |l| "#{target_base}_#{l}" }.find { |k| hash.key?(k) })
            tkey = found
            kind = :legacy
            base = target_base
          end
        end
        taken << tkey if tkey
        out << [ base, tkey, key, kind ]
      end
      hash.each_key do |key|
        next unless key.is_a?(String) && langs.include?(key[/_(en|es)\z/, 1]) && !taken.include?(key)

        base = key.sub(/_(en|es)\z/, "")
        next if EXEMPT.include?(base) || FIELDS[:native].include?(base) || FIELDS[:target_only].include?(base)
        next if hash.key?("#{base}_it")

        out << [ base, key, nil, :r1 ]
      end
      out
    end

    # Yields the string pairs under one field: a list by index, a table row by row.
    def leaves(pointer, base, target, italian, &block)
      if target.is_a?(Array) || italian.is_a?(Array)
        size = [ target.is_a?(Array) ? target.size : 0, italian.is_a?(Array) ? italian.size : 0 ].max
        size.times { |i| leaves("#{pointer}/#{i}", base, target.is_a?(Array) ? target[i] : nil, italian.is_a?(Array) ? italian[i] : nil, &block) }
      else
        yield pointer, base, target, italian
      end
    end

    # ---- folding ------------------------------------------------------------------------------------------------------------

    def fold_scope(node, lang, level)
      tr = {}
      out = fold_node(node, lang, level, tr)
      out["tr"] = tr unless tr.empty?
      out
    end

    def fold_node(node, lang, level, tr)
      case node
      when Hash
        out = node.dup
        twins(node, lang, "", r2: false).each do |_base, tkey, ikey, kind|
          next unless kind == :r1 && tkey && ikey

          record(tr, node[tkey], node[ikey])
          out.delete(tkey)
          out[ikey] = node[tkey]
        end
        out.to_h do |key, value|
          if value.is_a?(Array) && (inner = SCOPES[key]) && level == inner && value.all?(Hash)
            [ key, value.map { |element| fold_scope(element, lang, key == "cards" ? :card : :block) } ]
          else
            [ key, fold_node(value, lang, level, tr) ]
          end
        end
      when Array then node.map { |value| fold_node(value, lang, level, tr) }
      else node
      end
    end

    def record(tr, target, italian)
      if target.is_a?(Array) then target.each_with_index { |t, i| record(tr, t, italian.is_a?(Array) ? italian[i] : nil) }
      elsif target.is_a?(String) && italian.is_a?(String) then tr[target] = italian unless tr.key?(target)
      end
    end
  end
end
