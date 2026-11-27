module Grading
  module Closed
    # Words that an accent turns into ANOTHER word (D-403, round 9): «porque / porqué», «el / él», Italian «e / è». An added or a missing mark on one of
    # these is not an accent slip (D-296: es_accents, it_accents) but a different word, so the answer is wrong, or the declared error value when the
    # item declares it. One small list per language, in one place: a group holds the forms that differ only by a diacritic (grave and acute count as
    # one mark, as everywhere in the grader). Every other missing accent stays a slip.
    module DiacriticPairs
      SPANISH = [
        %w[porque porqué], %w[que qué], %w[como cómo], %w[cuando cuándo], %w[donde dónde], %w[quien quién], %w[cual cuál], %w[cuanto cuánto],
        %w[el él], %w[tu tú], %w[si sí], %w[mi mí], %w[se sé], %w[de dé], %w[mas más], %w[te té], %w[aun aún]
      ].freeze

      ITALIAN = [ %w[e è], %w[la là], %w[li lì], %w[se sé], %w[da dà], %w[ne né], %w[si sì] ].freeze

      GROUPS = { "spanish" => SPANISH, "italian" => ITALIAN }.freeze

      module_function

      # Does the answer differ from +accepted+ by the diacritic of a word that the subject's list holds? Both are normalised texts that are the same
      # once their accents are gone; the words are compared in order, and a text with another number of words is never judged here.
      def word_changed?(subject, answer, accepted)
        groups = folded(subject) or return false
        given = words(answer)
        wanted = words(accepted)
        return false unless given.size == wanted.size

        given.zip(wanted).any? do |a, b|
          a != b && groups.any? { |g| g.include?(a) && g.include?(b) }
        end
      end

      # The words of a text with grave and acute made one mark (the folded form the grader compares), as the lists write them.
      def words(text)
        Text.fold_direction(text).scan(/[\p{L}\p{M}]+/)
      end

      # The subject's groups in the folded spelling, so that a grave typed for an acute is still the same word.
      def folded(subject)
        @folded ||= GROUPS.transform_values { |lists| lists.map { |g| g.map { |w| Text.fold_direction(w) }.freeze }.freeze }.freeze
        @folded[subject.to_s]
      end
    end
  end
end
