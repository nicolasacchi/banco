module Speech
  # The samples of «Prova le voci» (D-283, D-359): each server voice says the first sentence (up to the first . ! or ?) of the fixed sample of its
  # language, `lesson2.voices.sentences.<lang>`; the same sentence for every voice of the language, so they can be compared. The browser asks for
  # them like any clip (voice number = the voice's place in its language's list).
  module Samples
    module_function

    def first_sentence(text) = text.to_s[/\A.*?[.!?](?=\s|\z)/m] || text.to_s

    def entries
      %w[it en es].flat_map do |lang|
        text = first_sentence(I18n.t("lesson2.voices.sentences.#{lang}", locale: :it, default: ""))
        next [] if text.strip.empty?

        Voices.for_language(lang).each_with_index.map do |voice, i|
          Plan::Entry.new(lang: lang, text: text, number: i + 1, voice: voice, key: Key.for(voice, text))
        end
      end
    end
  end
end
