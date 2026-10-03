require "digest"
require "json"

module Syllabus
  # Imports a programme file line by line into the append-only syllabus tables and
  # verifies it afterwards. A "line" is a newline-terminated physical line: the
  # file must end with a newline, and the lines rebuilt from the database must
  # hash to the file's sha256.
  class Importer
    Stats = Data.define(:count, :min, :max, :sha256) do
      def to_s = "count=#{count} min=#{min} max=#{max} sha256=#{sha256}"
    end

    # Transcriber scaffolding in a transcribed programme: a preamble that ends
    # with the first "---" line when the file opens with a "# " title, level-2
    # headings, a single italic subtitle line, page markers and figure placeholders.
    TRANSCRIPT_PATTERNS = [
      /\A## /,
      /\A\*[^*].*[^*]\*\z/,
      /\A\*\*Pagina \d+\*\*\z/,
      /\A> \[Figura:/
    ].freeze
    MARKER = /\A(★☆|☆★|★|☆)/

    # Line origin: blank lines and transcriber lines are "transcript" (not
    # citable); everything else is "pdf", the content of the original document.
    def self.origin_for(text, in_preamble:)
      return "transcript" if in_preamble || text.strip.empty?
      TRANSCRIPT_PATTERNS.any? { |pattern| pattern.match?(text) } ? "transcript" : "pdf"
    end

    # Sub-line addresses: cells of a markdown table row, or the bullets of a line
    # holding several "•" items. Returns a Hash {"A1" => "text"} or nil.
    def self.parts_for(text)
      segments =
        if text.start_with?("|")
          text.split("|").map(&:strip).reject(&:empty?)
        elsif text.scan("•").size > 1
          text.split("•").map(&:strip).reject(&:empty?)
        end
      return nil if segments.nil? || segments.size < 2
      segments.each_with_index.to_h { |segment, index| [ "A#{index + 1}", segment ] }
    end

    def self.split_lines(text)
      raise Error, "the text is not valid UTF-8" unless text.dup.force_encoding(Encoding::UTF_8).valid_encoding?
      text = text.dup.force_encoding(Encoding::UTF_8)
      raise Error, "the text is empty" if text.empty?
      raise Error, "the last line is not newline-terminated" unless text.end_with?("\n")
      text.chomp("\n").split("\n", -1)
    end

    def self.stats(text)
      lines = split_lines(text)
      Stats.new(lines.size, 1, lines.size, Digest::SHA256.hexdigest(text))
    end

    # Imports TEXT as source KEY. Importing the same text again is a no-op; a
    # different text under an existing key is refused (the log never changes).
    def self.import(key, text)
      lines = split_lines(text)
      stats = self.stats(text)
      existing = SyllabusSource.find_by(key: key)
      if existing
        return existing if existing.sha256 == stats.sha256
        raise Error, "source #{key} exists with a different text (sha256 #{existing.sha256})"
      end

      preamble_end = preamble_length(lines)
      SyllabusSource.transaction do
        source = SyllabusSource.create!(key: key, line_count: stats.count, sha256: stats.sha256)
        now = Time.current
        rows = lines.each_with_index.map do |line, index|
          parts = parts_for(line)
          { syllabus_source_id: source.id, number: index + 1, text: line,
            origin: origin_for(line, in_preamble: index < preamble_end),
            marker: line[MARKER, 1], parts_json: parts && JSON.generate(parts), created_at: now }
        end
        SyllabusLine.insert_all!(rows)
        source
      end
    end

    # Number of leading lines that are transcriber preamble (0 when absent).
    def self.preamble_length(lines)
      return 0 unless lines.first&.start_with?("# ")
      divider = lines.index("---")
      divider ? divider + 1 : 0
    end

    # Compares the file with what is stored; returns Stats or raises Error.
    def self.verify(key, text)
      file = stats(text)
      source = SyllabusSource.find_by(key: key) or raise Error, "source #{key} is not imported"
      numbers = source.lines.pluck(:number)
      rebuilt = Digest::SHA256.hexdigest(source.reconstructed_text)
      stored = Stats.new(numbers.size, numbers.min, numbers.max, rebuilt)
      problems = []
      problems << "line count #{stored.count} != #{file.count}" if stored.count != file.count
      problems << "line numbers are not 1..#{file.count}" unless numbers == (1..file.count).to_a
      problems << "sha256 of the stored lines #{rebuilt} != file #{file.sha256}" if rebuilt != file.sha256
      problems << "source sha256 #{source.sha256} != file #{file.sha256}" if source.sha256 != file.sha256
      raise Error, problems.join("; ") if problems.any?
      stored
    end
  end
end
