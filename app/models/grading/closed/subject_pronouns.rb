module Grading
  module Closed
    # A leading subject pronoun in a Spanish verb gap (round 10, D-408): «yo he ido» for the key «he ido», «nosotros hemos escrito» for
    # «hemos escrito», «yo me he duchado» for «me he duchado». Spanish drops the subject, so the pronoun is a right thing to write, not a word too many.
    #
    # Only in the subject spanish, only a pronoun that AGREES with the person of the key (the first words of the matched key or accept entry:
    # «he» is yo, «hemos» nosotros, «me» yo, «se» the third persons, the verb's ending otherwise; a key whose person cannot be read from its first
    # word accepts none), and never when the sentence shown already has a subject before the gap: the gap must open the sentence or follow only
    # words that cannot be a subject (the negation and the time words of LEADING). «tú he ido» and «yo hemos ido» stay wrong.
    module SubjectPronouns
      PERSONS = {
        "yo" => :yo, "tú" => :tu, "él" => :el, "ella" => :el, "usted" => :el,
        "nosotros" => :nos, "nosotras" => :nos, "vosotros" => :vos, "vosotras" => :vos,
        "ellos" => :ellos, "ellas" => :ellos, "ustedes" => :ellos
      }.freeze
      # The first word of a key that names its person by itself.
      VERBS = {
        "he" => %i[yo], "has" => %i[tu], "ha" => %i[el], "hemos" => %i[nos], "habéis" => %i[vos], "han" => %i[ellos],
        "había" => %i[yo el], "habías" => %i[tu], "habíamos" => %i[nos], "habíais" => %i[vos], "habían" => %i[ellos],
        "soy" => %i[yo], "estoy" => %i[yo], "voy" => %i[yo], "doy" => %i[yo], "eres" => %i[tu], "es" => %i[el], "somos" => %i[nos], "sois" => %i[vos],
        "son" => %i[ellos], "está" => %i[el], "estás" => %i[tu], "va" => %i[el], "vas" => %i[tu], "vamos" => %i[nos], "vais" => %i[vos], "van" => %i[ellos],
        "fui" => %i[yo], "fue" => %i[el], "fuiste" => %i[tu], "fuimos" => %i[nos], "fuisteis" => %i[vos], "fueron" => %i[ellos],
        "era" => %i[yo el], "eras" => %i[tu], "éramos" => %i[nos], "erais" => %i[vos], "eran" => %i[ellos]
      }.freeze
      # The ending of any other first word, longest first.
      ENDINGS = [
        [ "isteis", %i[vos] ], [ "asteis", %i[vos] ], [ "ieron", %i[ellos] ], [ "aron", %i[ellos] ], [ "amos", %i[nos] ], [ "emos", %i[nos] ], [ "imos", %i[nos] ],
        [ "aste", %i[tu] ], [ "iste", %i[tu] ], [ "áis", %i[vos] ], [ "éis", %i[vos] ], [ "ían", %i[ellos] ], [ "aban", %i[ellos] ], [ "ías", %i[tu] ],
        [ "abas", %i[tu] ], [ "ía", %i[yo el] ], [ "aba", %i[yo el] ], [ "ió", %i[el] ], [ "ís", %i[vos] ], [ "ás", %i[tu] ], [ "ré", %i[yo] ], [ "rá", %i[el] ],
        [ "an", %i[ellos] ], [ "en", %i[ellos] ], [ "as", %i[tu] ], [ "es", %i[tu] ], [ "ó", %i[el] ], [ "é", %i[yo] ], [ "í", %i[yo] ], [ "o", %i[yo] ],
        [ "a", %i[el] ]
      ].freeze
      # What a clitic at the start of a verb phrase says about the person; the others (lo, la, le, no) say nothing and are skipped.
      REFLEXIVES = { "me" => %i[yo], "te" => %i[tu], "se" => %i[el ellos], "nos" => %i[nos], "os" => %i[vos] }.freeze
      SKIPPED = %w[no lo la los las le les].freeze
      # Words that may stand before the gap without being its subject.
      LEADING = %w[no hoy ayer anoche anteayer ya aún todavía nunca jamás siempre esta mañana tarde noche semana].freeze

      module_function

      # Does +pronoun+ agree with the person of +entry+ (the matched key or accept entry)?
      def agrees?(pronoun, entry)
        person = PERSONS[pronoun]
        person ? persons(entry).include?(person) : false
      end

      # [pronoun, rest] when +text+ (as typed) starts with a subject pronoun and goes on, else nil. The pronoun is lower case with its accent kept.
      def split(text)
        first, rest = text.to_s.strip.split(/[[:space:]]+/, 2)
        pronoun = first.to_s.downcase.unicode_normalize(:nfc)
        return nil unless PERSONS.key?(pronoun) && rest.present?

        [ pronoun, rest ]
      end

      # May a pronoun open the answer, given the frame (nil: no sentence shown)? Its words before the gap, if any, are not a subject.
      def gap_open?(frame)
        frame.nil? || frame.prefix.all? { |w| LEADING.include?(w) }
      end

      # The persons that the first words of +entry+ (a key) can be of; empty when they say none.
      def persons(entry)
        words = entry.to_s.downcase.split(/[[:space:]]+/).map { |w| w.gsub(/\A[^[:alpha:]]+|[^[:alpha:]]+\z/, "") }.reject(&:empty?)
        clitic = nil
        words = words.drop_while do |w|
          clitic ||= REFLEXIVES[w]
          SKIPPED.include?(w) || REFLEXIVES.key?(w)
        end
        verb = words.first or return []
        found = VERBS[verb] || ENDINGS.find { |ending, _| verb.length > ending.length && verb.end_with?(ending) }&.last || []
        clitic ? found & clitic : found
      end
    end
  end
end
