# frozen_string_literal: true

module Banco
  module Schemas
    # The schemas of the bilingual courses (D-402). The JSON files in config/banco/schemas/ stay the schemas of every subject; for a subject that
    # teaches a language (english, spanish: Lessons::Lang.target) `Schemas.for_subject` reads them through `derive`, which adds
    #
    # - R1: for every property `foo_it` (but the teacher's own, Lessons::Bilingual::EXEMPT) the optional siblings `foo_en` and `foo_es`, with the
    #   same subschema, so an author writes the target text on the line above its Italian;
    # - R2: the optional Italian twins of the item keys that hold the subject's language without a suffix (`text_it` of an option and of a
    #   quote, `header_it`, `rows_it`, `final_it`);
    # - the marker `bilingual` (boolean) in the item, the lesson front matter and body, a course topic entry, the topic and the skill graph.
    #
    # Nothing is required by the derivation (the Italian is always there, the target is the new part), and a subject that does not teach a
    # language never meets it: its documents are checked against the files as they are, so a `_en` sibling or `bilingual: true` is E-SCHEMA there.
    module Bilingual
      NAMES = %w[item lesson course topic skill_graph diagram].freeze
      LANGS = %w[en es].freeze
      MARKER = { "type" => "boolean", "description" => "D-402: every student text of this revision is a pair, the target language under <base>_en|_es and its Italian under <base>_it." }.freeze
      # Where the marker goes: the schema, then the path of the object schema that gains the property ([] is the root).
      MARKERS = {
        "item" => [ [] ], "topic" => [ [] ], "skill_graph" => [ [] ],
        "lesson" => [ %w[$defs front_matter2], %w[$defs body2] ],
        "course" => [ %w[$defs topic_entry] ]
      }.freeze
      # D-402: `translate_material: false` says that the form material under it is target-only (Lessons::Bilingual::MATERIAL): an item (its root), a lesson check (a
      # check block, a step blank or an exercise's check, all `check_spec`), a `try` exercise, a `table` block and a figure of type `table`. Only `false` is a value:
      # a revision that has nothing to say about it translates everything.
      MATERIAL_MARKER = { "const" => false, "description" => "D-402: the form material of this exercise (the sentence with its blank, the options and rows that are forms, the final) is target-language only, with no Italian text; the instruction, hints, messages and solution steps stay paired." }.freeze
      MATERIAL_AT = {
        "item" => [ [] ],
        "lesson" => [ %w[$defs check_spec], %w[$defs exercise], %w[$defs b_table] ],
        "diagram" => [ %w[$defs table] ]
      }.freeze
      # The `_it` that the schema requires of a text that can be form material (an option, an exercise's sentence, a mistake's wrong and right): there the
      # target text is enough, `text_en` or `text_es` instead of `text_it` (the missing Italian of a text that is not material is E-LANG-PAIR-MISSING's).
      MATERIAL_REQUIRED = { "lesson" => { "id_text" => %w[text_it], "exercise" => %w[text_it], "b_mistake" => %w[wrong_it right_it] } }.freeze
      # R2: schema => { $defs name => { property => the Italian twin's name } }.
      R2 = {
        "item" => {
          "id_text" => { "text" => "text_it" }, "quote" => { "text" => "text_it" },
          "table" => { "header" => "header_it", "rows" => "rows_it" }, "solution" => { "final" => "final_it" }
        },
        # D-402, slice 3: the table block of a lesson and a figure of type `table` hold their cells in the subject's language, the Italian in `header_it` / `rows_it`.
        "lesson" => { "b_table" => { "header" => "header_it", "rows" => "rows_it" } },
        "diagram" => { "table" => { "header" => "header_it", "rows" => "rows_it" } }
      }.freeze
      # The words a bilingual item teaches, outside the first 3000 of the language (W-LANG-LEVEL), like a lesson's `teaches_en`: the item root only.
      TEACHES = { "type" => "array", "maxItems" => 40, "items" => { "type" => "string", "minLength" => 1, "maxLength" => 40 }, "description" => "D-402: words of the target language the item teaches, never linted as above the level." }.freeze
      TEACHES_AT = { "item" => [ [] ] }.freeze

      module_function

      # The schema named +name+ (a parsed hash) for a bilingual subject: a new hash, +schema+ is not changed.
      def derive(schema, name)
        out = copy(schema)
        siblings(out)
        R2.fetch(name.to_s, {}).each do |def_name, keys|
          properties = out.dig("$defs", def_name, "properties") or raise ArgumentError, "#{name}: no $defs/#{def_name}"
          keys.each do |key, twin|
            raise ArgumentError, "#{name}: no #{def_name}.#{key}" unless properties.key?(key)

            properties[twin] ||= copy(properties[key])
          end
        end
        MARKERS.fetch(name.to_s, []).each do |path|
          target = path.empty? ? out : out.dig(*path)
          raise ArgumentError, "#{name}: no #{path.join('/')}" unless target.is_a?(Hash) && target["properties"].is_a?(Hash)

          target["properties"]["bilingual"] ||= MARKER.dup
        end
        MATERIAL_AT.fetch(name.to_s, []).each do |path|
          target = path.empty? ? out : out.dig(*path)
          raise ArgumentError, "#{name}: no #{path.join('/')}" unless target.is_a?(Hash) && target["properties"].is_a?(Hash)

          target["properties"][Lessons::Bilingual::MARKER] ||= MATERIAL_MARKER.dup
        end
        MATERIAL_REQUIRED.fetch(name.to_s, {}).each do |def_name, keys|
          node = out.dig("$defs", def_name) or raise ArgumentError, "#{name}: no $defs/#{def_name}"
          node["required"] = Array(node["required"]) - keys
          node.delete("required") if node["required"].empty?
          keys.each do |key|
            base = key.delete_suffix("_it")
            node["allOf"] = Array(node["allOf"]) + [ { "anyOf" => [ key, *LANGS.map { |l| "#{base}_#{l}" } ].map { |k| { "required" => [ k ] } } } ]
          end
        end
        TEACHES_AT.fetch(name.to_s, []).each do |path|
          target = path.empty? ? out : out.dig(*path)
          LANGS.each { |lang| target["properties"]["teaches_#{lang}"] ||= TEACHES.dup }
        end
        out
      end

      # R1, at every object schema of the tree.
      def siblings(node)
        case node
        when Hash
          pair_properties(node["properties"]) if node["properties"].is_a?(Hash)
          node.each_value { |value| siblings(value) }
        when Array then node.each { |value| siblings(value) }
        end
      end

      def pair_properties(properties)
        properties.keys.each do |key|
          base = key[/\A(.+)_it\z/, 1]
          next if base.nil? || Lessons::Bilingual::EXEMPT.include?(base)

          LANGS.each { |lang| properties["#{base}_#{lang}"] ||= copy(properties[key]) }
        end
      end

      # A deep copy of a parsed JSON value (a schema is plain JSON: hashes, arrays, strings, numbers, booleans, nil).
      def copy(value) = JSON.parse(JSON.generate(value))
    end
  end
end
