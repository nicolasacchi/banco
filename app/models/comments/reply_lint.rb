module Comments
  # The tone lint of a reply the operator is about to send in the teacher's name (D-371). Advisory only: it returns warnings and
  # never refuses, never changes the text and never reaches the student. The list of blaming phrases and the length limit are
  # in config/banco/reply_lint.yml; the operator's tools (banco comments reply, bin/rails banco:comments:reply) print them
  # before the reply goes. The warnings are English, for the operator; the phrase is quoted as written in the list.
  module ReplyLint
    CONFIG_PATH = Rails.root.join("config/banco/reply_lint.yml").freeze

    # code: "blaming_phrase" (phrase says which) or "too_long" (length, max); message: one line for the operator.
    Warning = Struct.new(:code, :message, :phrase, :length, :max, keyword_init: true) do
      def to_h = { code: code, message: message, phrase: phrase, length: length, max: max }.compact
    end

    module_function

    def max_characters = config.fetch("max_characters")

    def phrases = config.fetch("phrases")

    # The warnings of a text, in the order of the list then the length; empty when the text reads fine (or is empty).
    def call(text)
      text = text.to_s.gsub(/\r\n?/, "\n").strip # as Comments::Responder will store it
      return [] if text.empty?

      hits = phrases.select { |phrase| matcher(phrase).match?(text) }
      # «tuo dispositivo» inside a hit «il tuo dispositivo» is the same fragment: one warning, for the longer phrase.
      hits = hits.reject { |phrase| hits.any? { |other| other != phrase && other.downcase.include?(phrase.downcase) } }
      found = hits.map do |phrase|
        Warning.new(code: "blaming_phrase", phrase: phrase, message: "reads as blaming the student: «#{phrase}»; say what the page does, not what he did")
      end
      found << Warning.new(code: "too_long", length: text.length, max: max_characters, message: "#{text.length} characters; over #{max_characters} is hard for him to read: shorten it") if text.length > max_characters
      found
    end

    def config
      @config ||= YAML.safe_load_file(CONFIG_PATH, aliases: false).tap do |c|
        raise ArgumentError, "max_characters must be positive" unless c["max_characters"].is_a?(Integer) && c["max_characters"].positive?
        raise ArgumentError, "phrases must be a list of non-empty strings" unless c["phrases"].is_a?(Array) && c["phrases"].all? { |p| p.is_a?(String) && !p.strip.empty? }
      end
    end

    # Whole words, any case: a letter before or after the phrase means it is part of another word («devi» is not «devia»).
    def matcher(phrase)
      @matchers ||= {}
      @matchers[phrase] ||= /(?<!\p{L})#{Regexp.escape(phrase).gsub("\\ ") { "\\s+" }}(?!\p{L})/i
    end

    def reset!
      @config = nil
      @matchers = nil
    end
  end
end
