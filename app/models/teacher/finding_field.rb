module Teacher
  # What the "field" of a finding is, in words for the teacher (D-222): which part of the item
  # the finding is about and whether S, the student, sees it. The field is free text written by
  # a reviewer ("stem_it", "options/2", "sources/1") or made by the software ("instances/2" for a
  # blind solve), so it is read by its path: the first word that names a part of the item decides.
  # Anything unknown gets a generic phrase that says so.
  module FindingField
    # The words of an item.json that reviewers and the software use in `field`, by part.
    KEYS = {
      stem: %w[stem stem_it prompt_stem_it prompt consegna question domanda],
      passage: %w[passage passage_it brano],
      material: %w[table quote figure caption_it alt_it asset assets header rows elements],
      options: %w[option options choices choice opzioni],
      format: %w[answer_format_it answer_format],
      steps: %w[steps_it steps],
      accept: %w[accept accepted must_accept must_reject accent_policy spelling_policy paradigm_forms case_sensitive allow_dot round_to unit],
      key: %w[key answer answers chiave risposta any_answer expected_it],
      errors: %w[errors error error_catalogue catalogue catalog error_value message_it description_it implicates catalogue_entry feedback],
      sources: %w[source sources ref refs fonti fonte programme programma fragment prima_line seconda_line lines line],
      solution: %w[solution final soluzione calculation],
      rubric: %w[rubric model_answer_it threshold points weight],
      metadata: %w[title component kind expected_seconds difficulty skill skills scope subject profile schema schema_version id],
      generator: %w[generator verify tests seed params parameters]
    }.freeze
    LOOKUP = KEYS.flat_map { |part, words| words.map { |w| [ w, part ] } }.to_h.freeze
    # Path words that only say where, never what.
    NOISE = %w[item item.json display sub_items instances instance revision].freeze

    module_function

    # The part (a symbol, the locale key under teacher.skill.field) a finding field is about; :other for the unknown.
    def key_for(field)
      words = field.to_s.strip.downcase.split(%r{[\s/.\[\]:,()]+}).reject(&:empty?)
      words.each do |word|
        next if word.match?(/\A\d+\z/) || NOISE.include?(word)

        return LOOKUP[word] if LOOKUP.key?(word)
      end
      return :instance if words.first&.start_with?("instance")

      :other
    end

    def phrase(field)
      I18n.t("teacher.skill.field.#{key_for(field)}", field: field.to_s.strip.first(60))
    end
  end
end
