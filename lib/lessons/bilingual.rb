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
  #
  # Form material is not translated (D-402). In an exercise that tests a target-language FORM (choose the form, fill the gap, judge a sentence, put forms in
  # order) the material, the sentence with its blank, the options or rows that are forms and the `final`, stays target-only: a translation would give the key away
  # («Quante/Quanti» -> Cuántas/Cuántos) or mislead. The instruction, the how-to-answer line, the hints, the messages and the solution steps stay paired.
  # `translate_material: false` on an item (its root), a lesson `check`, a `try` exercise or a `table` block says so for everything under it; a lesson
  # `mistake` block's `wrong` and `right` are always material. MATERIAL says which fields are material, `material?` decides, and a material field has no
  # pair: it is never an orphan, never missing, never folded into the `tr` table, never served with an Italian text (`translate_material` is served on the
  # check so the page does not look for one).
  # A lesson check's own `sentence_<lang>` (SENTENCE) is material with no marker needed: a form check (choice, matching, tiles...) has nowhere else to put its sentence.
  module Bilingual
    # Keys (their base, without `_it`) that are never paired: the teacher's own words, what points at the Italian textbook, what is graded or
    # typed by a program. `rubric.points[].expected_it` and the short answer's `model_answer_it` follow Q5 of D-402: the rubric stays Italian, the
    # model answer is a pair like any other text (`model_answer_en` is the English one).
    EXEMPT = %w[description choice_only_reason notes reachable_ok book reason scope_reason expected input].freeze

    FIELDS = {
      # R2: bare keys that hold the subject's language. Base => the pointer of the hash that holds it (the key's twin is `<base>_it`). The table of a lesson
      # (the block, at /cards/N/blocks/M) and of a figure of type `table` (its pointer ends /diagram or /schema) is paired like an item's table (D-402, slice 3):
      # `header` and `rows` there only count when the hash is of `type: table` (TYPED), so the `rows` of a mirror or a word_parts figure are not table rows.
      r2: {
        "text" => %r{/(?:options|elements|left|right)/\d+\z|/quote\z},
        "header" => %r{/(?:table|diagram|schema)\z|/blocks/\d+\z},
        "rows" => %r{/(?:table|diagram|schema)\z|/blocks/\d+\z},
        "final" => %r{/solution\z}
      }.freeze,
      # The pointers of R2's `header` and `rows` that name a block or a figure of any type: the hash must say `type: table` to hold a table there.
      table_typed: %r{/(?:diagram|schema)\z|/blocks/\d+\z}.freeze,
      # The labels of a flow's edges (D-402): `edges` is a list of [from, to, label] with the target label in the third place; the Italian labels are the list
      # `edges_it`, one for each edge in the same order (null for an edge without a label). Value: the figure's `type`.
      edge_labels_type: "flow",
      # The figure whose own text is target-language material, never a pair: a `sentence` figure's `text_<lang>` (and its states'), with the parts in `fragments`.
      # Its translation lives in `alt_it` and `caption_it`, which pair as usual. Value: the figure's `type`.
      sentence_type: "sentence",
      # Pairs that a figure or a block already draws by its own shape, as (Italian base => target base): a dialogue line's `text_en` and
      # `gloss_it`, a word_parts word's `form_en` and `label_it`. They count as pairs for the validators and are never folded.
      legacy: { "gloss" => "text", "label" => "form" }.freeze,
      # Both sides are drawn side by side by the figure itself (mirror: `pieces_it` and `pieces_en`): never folded, never an orphan.
      native: %w[pieces].freeze,
      # What a `word_parts` word says of its pieces and of the whole word (decode view): an Italian gloss for the student, like `label_it`, so the word's `form_<lang>`
      # needs no `parts_<lang>` or `meaning_<lang>` beside it. Never a pair, never an orphan when `_it` stands alone; written as a target pair (`parts_es` and
      # `parts_it`) it is an ordinary pair and both sides must be complete.
      gloss: %w[parts meaning].freeze,
      # Target text that is the exercise's own material and is translated by the prompt around it, never piece by piece (slice 3 and 5, D-402): a span_select's
      # sentence (`text_en|es` of a check with that component) and its spans, the tiles, a `listen` text, the parts of a sentence figure, the marks of a tense
      # timeline (their `text_en|es` is the sentence the mark stands for; the schema has no `text_it` for it). Never an orphan.
      fragments: %r{/(?:spans|tiles|parts|marks)/\d+\z|/listen\z}.freeze,
      # Target-language data with no Italian twin by design (vocabulary lists, forms, the `teaches_en` lexicon): never an orphan.
      target_only: %w[teaches form base past participle verb cells].freeze
    }.freeze

    # The marker of form material: `translate_material: false` (the only value that means anything; true is what no marker says).
    MARKER = "translate_material"
    # Form material, by base and the pointer of the hash that holds it, once a marker is in force above it (see the module comment): an instance's
    # `display.stem`, the `text` of an option, element or row (items and lesson checks), the `final` of a solution or of a `try` exercise and the `text` of that
    # exercise (the sentence with its blank). A `table`'s `header` and `rows` are material under the marker when the hash is of `type: table`.
    MATERIAL = {
      "stem" => %r{/display\z},
      "text" => %r{/(?:options|elements|left|right)/\d+\z|/exercises/\d+\z},
      "final" => %r{/solution\z|/exercises/\d+\z}
    }.freeze
    # What a `mistake` block holds is material with no marker: the wrong and the right form (a translation of either gives the same Italian for both).
    MISTAKE_MATERIAL = %w[wrong right].freeze
    # The sentence of a lesson check on form material: `sentence_en|es`, drawn above the options (or the rows, the tiles...), target-only whatever the marker says. It
    # has no Italian twin (a `sentence_it` is E-LANG-PAIR-ORPHAN) and is served in the `sentence_it` slot with no `tr` entry. Only a hash that is a check (`component`) has one.
    SENTENCE = "sentence"

    # The levels of a served lesson that own a `tr` table: the body, each card, each block of a card.
    SCOPES = { "cards" => :body, "blocks" => :card }.freeze

    module_function

    # Every pair of +doc+ (a body, a front matter, an item, a figure, a course or a skill graph) as (pointer, base, target, italian):
    # the pointer is the target field's (where it would be when missing), +target+ or +italian+ is nil when that side is missing. A list
    # pairs by index (a missing or extra item is a nil side), a table row by row. +lang+ is the subject's language, nil for any of them.
    # Orphans come out too (a target without its Italian, an Italian without its target); the validators decide what each means. Form material
    # (see the module comment) has no pair and does not come out; +material+ says that the marker is already in force above +node+ (a walk that
    # starts below the item's root, an instance).
    def pairs(node, lang = nil, pointer = "", sentence = false, material = false, &block)
      return enum_for(:pairs, node, lang, pointer, sentence, material) unless block

      case node
      when Hash
        sentence = in_sentence?(node, sentence)
        material = material_in?(node, material)
        twins(node, lang, pointer, sentence: sentence, material: material).each do |base, tkey, ikey, kind|
          next if kind == :material

          if kind == :edges then edge_pairs(node, pointer, &block)
          else leaves("#{pointer}/#{tkey || "#{base}_#{lang || Lang.sibling_lang(node, base) || Lang::PAIR_LANGS.first}"}", base, tkey && node[tkey], ikey && node[ikey], &block)
          end
        end
        node.each { |k, v| pairs(v, lang, "#{pointer}/#{k}", sentence, material, &block) if v.is_a?(Hash) || v.is_a?(Array) }
      when Array
        node.each_with_index { |v, i| pairs(v, lang, "#{pointer}/#{i}", sentence, material, &block) if v.is_a?(Hash) || v.is_a?(Array) }
      end
    end

    # The form material of +node+ that has a field: yields (pointer, base, target_key, italian_key), the pointer being the HASH's, the keys as written
    # (+target_key+ is nil when the target text is under no sibling key of the hash; +italian_key+ is nil when there is no Italian, the usual case).
    def material_fields(node, lang = nil, pointer = "", sentence = false, material = false, &block)
      return enum_for(:material_fields, node, lang, pointer, sentence, material) unless block

      case node
      when Hash
        sentence = in_sentence?(node, sentence)
        material = material_in?(node, material)
        twins(node, lang, pointer, sentence: sentence, material: material).each do |base, tkey, ikey, kind|
          yield pointer, base, tkey, ikey if kind == :material
        end
        node.each { |k, v| material_fields(v, lang, "#{pointer}/#{k}", sentence, material, &block) if v.is_a?(Hash) || v.is_a?(Array) }
      when Array
        node.each_with_index { |v, i| material_fields(v, lang, "#{pointer}/#{i}", sentence, material, &block) if v.is_a?(Hash) || v.is_a?(Array) }
      end
    end

    # The pointers (of the target fields) of the form material of +node+ that holds a target text, as a set: the lint of the level of a word leaves them.
    def material_pointers(node, lang = nil, material = false)
      material_fields(node, lang, "", false, material).filter_map { |pointer, base, tkey, _| "#{pointer}/#{tkey || base}" if tkey }.to_set
    end

    # True inside a `sentence` figure (the figure itself, its states, its parts): +inherited+ is what the parent said.
    def in_sentence?(hash, inherited = false) = inherited || hash["type"] == FIELDS[:sentence_type]

    # Is +hash+ a flow figure whose edges may carry labels (the pair of `edges` and `edges_it`)?
    def edge_labels?(hash) = hash["type"] == FIELDS[:edge_labels_type] && hash["edges"].is_a?(Array)

    # The label of each edge of a flow (its third place) as a list the size of `edges`: a string or nil.
    def edge_labels(hash) = hash["edges"].map { |edge| edge.is_a?(Array) && edge[2].is_a?(String) ? edge[2] : nil }

    # Yields the pairs of a flow's edge labels, (pointer of the label, "edges", label, Italian), one for each edge; an edge with neither is no pair.
    def edge_pairs(hash, pointer)
      labels = edge_labels(hash)
      italians = hash["edges_it"].is_a?(Array) ? hash["edges_it"] : []
      [ labels.size, italians.size ].max.times do |i|
        target = labels[i]
        italian = italians[i]
        yield "#{pointer}/edges/#{i}/2", "edges", target, italian unless target.nil? && italian.nil?
      end
    end

    # True under a hash that says `translate_material: false` (the hash itself, everything below it): +inherited+ is what the parent said.
    def material_in?(hash, inherited = false) = inherited || hash[MARKER] == false

    # Is +base+ of +hash+, at +pointer+, form material? +marker+: the marker is in force (material_in?).
    def material?(hash, base, pointer, marker)
      return true if hash["type"] == "mistake" && MISTAKE_MATERIAL.include?(base)
      return true if base == SENTENCE && hash.key?("component")
      return hash["type"] == "table" if marker && %w[header rows].include?(base)

      marker && MATERIAL[base]&.match?(pointer) ? true : false
    end

    # Is +base+ of +hash+, at +pointer+, a key of rule R2 (a bare key that holds the target text)? `header` and `rows` of a block or a figure must belong to a table.
    def r2?(hash, base, pointer)
      FIELDS[:r2][base]&.match?(pointer) && (!FIELDS[:table_typed].match?(pointer) || !%w[header rows].include?(base) || hash["type"] == "table")
    end

    # The Italian layer of +doc+ (§4.2 rule 5): each pair is replaced by its Italian, so a scan for the key finds what the student reads
    # with the translation open. R1 keys keep `<base>_it` and lose the target sibling; R2 keys take the Italian in the bare key. Orphans,
    # legacy and native pairs stay as they are. Form material has no Italian: its R1 target text (a stem) is left out of the layer, the bare key of
    # an R2 field (an option's text, a final) stays as it is, the same text the student reads with the translation open. A new object; +doc+ is not changed.
    def italian_layer(doc, pointer = "", sentence = false, material = false)
      case doc
      when Hash
        out = doc.dup
        sentence = in_sentence?(doc, sentence)
        material = material_in?(doc, material)
        twins(doc, nil, pointer, sentence: sentence, material: material).each do |base, tkey, ikey, kind|
          if kind == :material
            out.delete(tkey) if tkey && tkey != base
            out.delete(ikey) if ikey
            next
          end
          next if kind == :legacy || tkey.nil? || ikey.nil?

          if kind == :edges
            italians = Array(doc[ikey])
            out["edges"] = doc["edges"].each_with_index.map { |edge, i| edge.is_a?(Array) && edge[2].is_a?(String) && italians[i].is_a?(String) ? [ *edge.first(2), italians[i] ] : edge }
            out.delete(ikey)
          elsif kind == :r2
            out[base] = doc[ikey]
            out.delete(ikey)
          else out.delete(tkey)
          end
        end
        out.to_h { |k, v| [ k, v.is_a?(Hash) || v.is_a?(Array) ? italian_layer(v, "#{pointer}/#{k}", sentence, material) : v ] }
      when Array then doc.each_with_index.map { |v, i| v.is_a?(Hash) || v.is_a?(Array) ? italian_layer(v, "#{pointer}/#{i}", sentence, material) : v }
      else doc
      end
    end

    # A served lesson body (the StudentBody whitelist's projection of a bilingual one) in the shape the renderer already reads (§2.5):
    # each R1 pair `foo_<lang>` + `foo_it` becomes `foo_it` holding the TARGET text, and the Italian goes to `tr`, a table {target string =>
    # Italian} on the nearest scope (the body, a card, a block of a card). The root gains `lang`. A list pairs by index. Fields without a
    # pair, legacy pairs (dialogue) and native pairs (mirror) are left as served. Two equal target strings in one scope keep the first Italian
    # (the validator refuses the conflict, E-LANG-PAIR-CONFLICT). Form material is served in the slot with no entry in `tr` and no Italian. A new object; +served+ is not changed.
    def fold(served, lang)
      { "lang" => lang }.merge(fold_scope(served, lang, :body))
    end

    # ---- walking ------------------------------------------------------------------------------------------------------------

    # The pairs of one hash as [[base, target_key, italian_key, kind]]; a side that is missing is nil; kind is :r1, :r2, :legacy or :material (form material,
    # R1 or R2: it has no pair). +sentence+: the hash is inside a `sentence` figure, whose `text` is target-only (see FIELDS[:sentence_type]); a walker passes
    # `in_sentence?`. +material+: the marker is in force (`material_in?`).
    def twins(hash, lang, pointer, r2: true, sentence: false, material: false)
      langs = lang ? [ lang ] : Lang::PAIR_LANGS
      out = []
      taken = []
      hash.each_key do |key|
        next unless key.is_a?(String) && (base = key[/\A(.+)_it\z/, 1])
        next if EXEMPT.include?(base) || FIELDS[:native].include?(base) || (sentence && base == "text")

        tkey = langs.map { |l| "#{base}_#{l}" }.find { |k| hash.key?(k) }
        kind = :r1
        if tkey.nil? && base == "edges" && edge_labels?(hash)
          tkey = "edges"
          kind = :edges
        end
        if tkey.nil? && r2 && hash.key?(base) && r2?(hash, base, pointer)
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
        next if tkey.nil? && FIELDS[:gloss].include?(base) && langs.any? { |l| hash.key?("form_#{l}") }

        kind = :material if kind != :legacy && material?(hash, base, pointer, material)
        taken << tkey if tkey
        out << [ base, tkey, key, kind ]
      end
      # a flow's labelled edges without their `edges_it`: the target labels are orphans (the same list the pair would have)
      out << [ "edges", "edges", nil, :edges ] if edge_labels?(hash) && !hash.key?("edges_it") && edge_labels(hash).any?
      hash.each_key do |key|
        next unless key.is_a?(String) && langs.include?(key[/_(en|es)\z/, 1]) && !taken.include?(key)

        base = key.sub(/_(en|es)\z/, "")
        next if EXEMPT.include?(base) || FIELDS[:native].include?(base) || FIELDS[:target_only].include?(base)
        next if base == "text" && (sentence || hash["component"] == "span_select" || FIELDS[:fragments].match?(pointer))
        next if hash.key?("#{base}_it")

        out << [ base, key, nil, material?(hash, base, pointer, material) ? :material : :r1 ]
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

    def fold_scope(node, lang, level, sentence = false, material = false)
      tr = {}
      out = fold_node(node, lang, level, tr, sentence, "", material)
      out["tr"] = tr unless tr.empty?
      out
    end

    def fold_node(node, lang, level, tr, sentence = false, pointer = "", material = false)
      case node
      when Hash
        out = node.dup
        sentence = in_sentence?(node, sentence)
        material = material_in?(node, material)
        twins(node, lang, pointer, r2: false, sentence: sentence, material: material).each do |base, tkey, ikey, kind|
          if kind == :edges && ikey
            record(tr, edge_labels(node), node[ikey])
            out.delete(ikey)
            next
          end
          if kind == :material
            next unless tkey && tkey != base

            out.delete(tkey)
            out["#{base}_it"] = node[tkey]
            next
          end
          next unless kind == :r1 && tkey && ikey

          record(tr, node[tkey], node[ikey])
          out.delete(tkey)
          out[ikey] = node[tkey]
        end
        out.to_h do |key, value|
          if value.is_a?(Array) && (inner = SCOPES[key]) && level == inner && value.all?(Hash)
            [ key, value.map { |element| fold_scope(element, lang, key == "cards" ? :card : :block, sentence, material) } ]
          else
            [ key, fold_node(value, lang, level, tr, sentence, "#{pointer}/#{key}", material) ]
          end
        end
      when Array then node.each_with_index.map { |value, i| fold_node(value, lang, level, tr, sentence, "#{pointer}/#{i}", material) }
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
