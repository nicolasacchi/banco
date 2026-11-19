module Changelog
  # The curated entries of «Novità» (D-375), read from config/banco/changelog.yml: one hand-written entry per change that the student or the teacher
  # can see, added in the same commit as the change. Nothing here is generated, so every word the student reads is text that git holds.
  #
  #   Changelog::Entries.all                # => [Entry] newest first (same day: the later in the file first)
  #   Changelog::Entries.for(:student)      # the entries whose audience includes the student
  #   Changelog::Entries.for(:teacher)      # every entry: the teacher reads what the student reads and what is for the teacher alone
  #   Changelog::Entries.errors(raw)        # the problems of a parsed file, [] when it is valid
  module Entries
    DEFAULT_PATH = Rails.root.join("config/banco/changelog.yml").freeze
    AUDIENCES = %w[student teacher].freeze
    KINDS = %w[software content fix].freeze
    REQUIRED = %w[id date audience kind title_it body_it].freeze
    OPTIONAL = %w[title_en body_en decisions topics link].freeze
    ID = /\A[a-z0-9][a-z0-9-]{2,63}\z/
    DECISION = /\AD-\d{3,}\z/
    TITLE_MAX = 70
    BODY_MAX = 330
    SENTENCES_MAX = 3
    LINK = %r{\A/[A-Za-z0-9/_.\-]{0,99}\z}
    # A decision number is the teacher's word; jargon is what the student has no use for. Checked on the student's texts only.
    DECISION_IN_TEXT = /\bD-\d{2,}\b/
    JARGON = /\b(api|json|token|database|ledger|endpoint|csrf|backend|deploy|cache|migrazione|migration|rails|ruby|cli|schema\.org)\b/i

    Entry = Data.define(:id, :date, :audience, :kind, :title_it, :body_it, :title_en, :body_en, :decisions, :topics, :link) do
      def student? = audience.include?("student")

      def teacher? = audience.include?("teacher")

      # The Italian text, or the English twin for a student reading the app in English (the teacher's pages are always Italian).
      def title(locale = :it) = locale.to_s == "en" && title_en ? title_en : title_it

      def body(locale = :it) = locale.to_s == "en" && body_en ? body_en : body_it

      def at = date.in_time_zone
    end

    class Invalid < StandardError; end

    # Where the file is; tests point it at a file of their own.
    mattr_accessor :path, default: DEFAULT_PATH

    module_function

    def all
      @all = nil if @loaded_from != path
      @loaded_from = path
      @all ||= parse(File.read(path))
    end

    def reset! = (@all = nil)

    def for(audience)
      audience = audience.to_s
      raise ArgumentError, "audience is student or teacher" unless AUDIENCES.include?(audience)

      audience == "teacher" ? all : all.select(&:student?)
    end

    # The entries dated on or after +date+ (a Date), newest first.
    def since(entries, date) = date ? entries.select { |e| e.date >= date } : entries

    # Parses the text of the file into entries, newest first; raises Invalid listing every problem.
    def parse(text)
      raw = YAML.safe_load(text, permitted_classes: [ Date ], aliases: false)
      problems = errors(raw)
      raise Invalid, problems.join("; ") if problems.any?

      raw.fetch("entries").each_with_index.map { |hash, index| [ build(hash), index ] }
         .sort_by { |entry, index| [ -entry.date.jd, -index ] }.map(&:first)
    end

    def build(hash)
      Entry.new(id: hash["id"], date: hash["date"], audience: hash["audience"], kind: hash["kind"], title_it: hash["title_it"], body_it: hash["body_it"],
                title_en: hash["title_en"], body_en: hash["body_en"], decisions: Array(hash["decisions"]), topics: Array(hash["topics"]), link: hash["link"])
    end

    # The problems of a parsed file, as sentences naming the entry; [] when it is valid.
    def errors(raw)
      return [ "the file is a mapping with an `entries` list" ] unless raw.is_a?(Hash) && raw.keys == [ "entries" ] && raw["entries"].is_a?(Array)

      found = []
      ids = raw["entries"].filter_map { |e| e["id"] if e.is_a?(Hash) }
      (ids.tally.select { |_, n| n > 1 }.keys).each { |id| found << "id #{id.inspect} is used twice" }
      raw["entries"].each_with_index { |entry, index| found.concat(entry_errors(entry, index)) }
      found
    end

    def entry_errors(entry, index)
      return [ "entry #{index + 1} is not a mapping" ] unless entry.is_a?(Hash)

      name = "entry #{entry['id'].inspect}"
      found = []
      (entry.keys - REQUIRED - OPTIONAL).each { |key| found << "#{name} has an unknown key #{key.inspect}" }
      REQUIRED.each { |key| found << "#{name} needs #{key}" if entry[key].nil? || entry[key].to_s.strip.empty? }
      found << "#{name}: id is lower case words and hyphens" unless entry["id"].to_s.match?(ID)
      found << "#{name}: date is a day such as 2026-11-19" unless entry["date"].is_a?(Date)
      audience = entry["audience"]
      if audience.is_a?(Array) && audience.any? && audience.uniq == audience && (audience - AUDIENCES).empty?
        student = audience.include?("student")
      else
        found << "#{name}: audience is a list of student, teacher or both"
        student = false
      end
      found << "#{name}: kind is one of #{KINDS.join(', ')}" unless KINDS.include?(entry["kind"])
      found.concat(text_errors(name, entry, "it", student: student))
      found.concat(text_errors(name, entry, "en", student: student))
      found.concat(list_errors(name, entry))
      found
    end

    # title_it/body_it always; the English twin is required for the student and, when there is one, is checked the same way.
    def text_errors(name, entry, language, student:)
      title = entry["title_#{language}"]
      body = entry["body_#{language}"]
      found = []
      if language == "en"
        found << "#{name}: a student entry needs title_en and body_en" if student && (title.to_s.strip.empty? || body.to_s.strip.empty?)
        found << "#{name}: title_en and body_en come together" if title.to_s.strip.empty? != body.to_s.strip.empty?
        return found if title.to_s.strip.empty? && body.to_s.strip.empty?
      end
      return found unless title.is_a?(String) && body.is_a?(String)

      found << "#{name}: title_#{language} is at most #{TITLE_MAX} characters" if title.length > TITLE_MAX
      found << "#{name}: body_#{language} is at most #{BODY_MAX} characters" if body.length > BODY_MAX
      found << "#{name}: body_#{language} is 1 to #{SENTENCES_MAX} short sentences (it has #{sentences(body)})" unless (1..SENTENCES_MAX).cover?(sentences(body))
      if student || language == "en"
        found << "#{name}: the student's text has no decision number" if [ title, body ].any? { |t| t.match?(DECISION_IN_TEXT) }
        found << "#{name}: the student's text has jargon (#{[ title, body ].filter_map { |t| t[JARGON] }.first})" if [ title, body ].any? { |t| t.match?(JARGON) }
        found << "#{name}: the student's text reads as blaming" if language == "it" && (Comments::ReplyLint.call(body) + Comments::ReplyLint.call(title)).any? { |w| w.code == "blaming_phrase" }
      end
      found
    end

    def list_errors(name, entry)
      found = []
      if entry.key?("decisions")
        list = entry["decisions"]
        found << "#{name}: decisions is a list such as [D-366]" unless list.is_a?(Array) && list.any? && list.all? { |d| d.to_s.match?(DECISION) } && list.uniq == list
      end
      if entry.key?("topics")
        list = entry["topics"]
        found << "#{name}: topics is a list of topic keys" unless list.is_a?(Array) && list.any? && list.all? { |t| t.to_s.match?(/\A#{Comments::Pages::TOPIC}\z/) }
      end
      found << "#{name}: link is a path of the app such as /schemas" if entry.key?("link") && !entry["link"].to_s.match?(LINK)
      found
    end

    # How many sentences a text has: stops (. ! ?) followed by a space or the end.
    def sentences(text) = text.to_s.strip.split(/(?<=[.!?])\s+/).size
  end
end
