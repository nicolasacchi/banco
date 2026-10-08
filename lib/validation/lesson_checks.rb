# frozen_string_literal: true

module Validation
  # The synchronous checks of a lesson (A2.1, A3.2): the parse (Lessons::Parser), the skills it names, the
  # kind's scope and refs, citations, the limits of the eight sections, readability of the text S reads.
  # Nothing is written. Thresholds: config/banco/validation_rules.yml, block lesson.
  module LessonChecks
    Outcome = Struct.new(:findings, :parsed, keyword_init: true) do
      def body = parsed&.body
    end

    WORD = /[A-Za-zÀ-ÿ0-9']+/
    SKIP_IN_LINT = %w[W-GULPEASE].freeze

    module_function

    # +md+: the text of lesson.md; +subject+: the subject key of the submit.
    def call(md, subject:, context:)
      findings = Findings.new
      parsed = Lessons::Parser.call(md, findings)
      return Outcome.new(findings: findings, parsed: nil) unless parsed

      fm = parsed.front_matter
      if fm["subject"].is_a?(String) && fm["subject"] != subject
        findings.add("E-SCHEMA", "/front_matter/subject", "the lesson is for #{fm['subject']}, submitted for #{subject}", rule: "subject")
      end
      if fm["skills"].is_a?(Array) && fm["uses"].is_a?(Array) && (both = fm["skills"] & fm["uses"]).any?
        findings.add("E-SCHEMA", "/front_matter/uses", "#{both.join(', ')} is in skills: uses names other skills", rule: "uses_in_skills")
      end
      skills_known(fm, subject, context, findings)
      refs(fm, context, findings)
      sections(parsed, findings)
      exercises(parsed, findings)
      readability(parsed, findings)
      if parsed.body
        shape = Findings.new
        SchemaCheck.call("lesson", parsed.body, shape, prefix: "/body")
        shape.each { |f| findings.add(f.code, f.field, f.message, **f.detail) }
      end
      Outcome.new(findings: findings, parsed: parsed)
    end

    def words(text) = text.to_s.gsub(/\$[^$]*\$/, " formula ").scan(WORD).size

    def rule(*path) = Rules.get(:lesson, *path)

    # skills and uses are skills of the graph, the course map, or an approved graph of another subject.
    def skills_known(fm, subject, context, findings)
      %w[skills uses].each do |member|
        next unless fm[member].is_a?(Array)

        fm[member].each_with_index do |key, i|
          next unless key.is_a?(String) && key.match?(/\A[a-z_]+\.[a-z0-9-]+\z/)

          findings.add("E-SKILL-UNKNOWN", "/front_matter/#{member}/#{i}", "#{key} is not a skill of the #{subject} graph or course map, nor of an approved graph", skill: key) if context.skill(key).nil?
        end
      end
    end

    # The kind's scope and refs (E-LESSON-REFS) and the citations (E-SOURCE).
    def refs(fm, context, findings)
      list = fm["refs"]
      return unless list.is_a?(Array) && list.all?(Hash)

      list.each_with_index { |ref, j| GraphChecks.citation(ref, "/front_matter/refs/#{j}", context, findings) if ref["source"] && ref["line"] && ref["fragment"] }
      seconda = Rules.get(:course, :seconda_source)
      prima = Rules.get(:coverage, :prima_source)
      has = ->(source, role) { list.any? { |r| r["source"] == source && r["role"] == role } }
      add = ->(why) { findings.add("E-LESSON-REFS", "/front_matter/refs", "a #{fm['kind']} lesson #{why}", rule: "refs-#{fm['kind']}") }
      case fm["kind"]
      when "ripasso"
        findings.add("E-LESSON-REFS", "/front_matter/scope", "a ripasso has scope studied, integration_studied or in_progress, not #{fm['scope'].inspect}", rule: "scope") unless %w[studied integration_studied in_progress].include?(fm["scope"])
        add.call("needs a needed_by ref on #{seconda}") unless has.call(seconda, "needed_by")
        findings.add("E-LESSON-REFS", "/front_matter/refs", "a ripasso needs a taught_in ref on #{prima}", rule: "refs-ripasso-prima") unless has.call(prima, "taught_in")
      when "ponte"
        findings.add("E-LESSON-REFS", "/front_matter/scope", "a ponte has scope middle_school or not_in_prima, not #{fm['scope'].inspect}", rule: "scope") unless %w[middle_school not_in_prima].include?(fm["scope"])
        add.call("needs a needed_by ref on #{seconda}") unless has.call(seconda, "needed_by")
        add.call("may cite the previous year's programme only as taught_in") if list.any? { |r| r["source"] == prima && r["role"] != "taught_in" }
      when "lezione"
        findings.add("E-LESSON-REFS", "/front_matter/scope", "a lezione has scope seconda, not #{fm['scope'].inspect}", rule: "scope") unless fm["scope"] == "seconda"
        add.call("needs a taught_in ref on #{seconda}") unless has.call(seconda, "taught_in")
      end
    end

    def sections(parsed, findings)
      secs = parsed.sections
      lesson_text = secs.reject { |k, _| %w[try solutions].include?(k) }.values.map(&:text).join("\n")
      count = words(lesson_text)
      findings.add("E-LESSON-WORDS", "/sections", "the lesson text has #{count} words outside Prova tu and Soluzioni (at most #{rule(:max_words)})", words: count) if count > rule(:max_words)

      all = words(parsed.body_text)
      bold = parsed.body_text.scan(/\*\*(.+?)\*\*/).sum { |(inner)| words(inner) }
      if all.positive? && bold.to_f / all > rule(:max_bold_ratio)
        findings.add("E-LESSON-BOLD", "/sections", "#{(bold * 100.0 / all).round(1)}% of the words are bold (at most #{(rule(:max_bold_ratio) * 100).round}%): bold only the keywords", ratio: (bold.to_f / all).round(3))
      end

      page_text = parsed.body_text.gsub(rule(:book_line), "") + " " + parsed.front_matter["title_it"].to_s
      if page_text.match?(Regexp.new(rule(:page_pattern), Regexp::IGNORECASE))
        findings.add("E-LESSON-PAGE", "/sections", "a page number: never name a page of the book", rule: "page")
      end

      book(secs["book_it"], findings)
      summary(secs["summary_it"], findings)
      mistakes(secs["mistakes_it"], findings)
      why(secs["why_it"], findings)
    end

    def book(section, findings)
      return unless section

      line = rule(:book_line)
      if !section.text.start_with?(line)
        findings.add("E-LESSON-BOOK", "/sections/book_it", "Sul libro must start with the line: #{line}", rule: "start")
      elsif words(section.text.delete_prefix(line)) > rule(:book_extra_words)
        findings.add("E-LESSON-BOOK", "/sections/book_it", "Sul libro adds more than #{rule(:book_extra_words)} words to the fixed line", rule: "extra")
      end
    end

    def summary(section, findings)
      return unless section&.blocks

      lo, hi = rule(:summary_points)
      blocks = section.blocks
      if blocks.size != 1 || blocks.first.type != :ul
        findings.add("E-LESSON-SUMMARY", "/sections/summary_it", "In sintesi must be exactly one list of points (each line starts with - )", rule: "shape")
      elsif !(lo..hi).cover?(blocks.first.items.size)
        findings.add("E-LESSON-SUMMARY", "/sections/summary_it", "In sintesi has #{blocks.first.items.size} points (#{lo} to #{hi})", rule: "count")
      end
    end

    def mistakes(section, findings)
      return unless section&.blocks

      n = section.blocks.sum { |b| b.type == :p ? 0 : b.items.size }
      findings.add("W-LESSON-MISTAKES", "/sections/mistakes_it", "Errori da evitare has #{n} list item(s) (at least #{rule(:mistakes_min)})", count: n) if n < rule(:mistakes_min)
    end

    def why(section, findings)
      return unless section

      n = Readability.sentences_of(Readability.strip_markup(section.text.gsub(Readability::MATH, " m "))).size
      lo, hi = rule(:why_sentences)
      findings.add("W-LESSON-WHY", "/sections/why_it", "Perché ti serve has #{n} sentence(s) (#{lo} to #{hi})", count: n) unless (lo..hi).cover?(n)
    end

    def exercises(parsed, findings)
      list = parsed.exercises
      return unless list

      lo, hi = rule(:exercises)
      findings.add("E-LESSON-EXERCISES", "/sections/try", "Prova tu has #{list.size} exercises (#{lo} to #{hi})", rule: "range", count: list.size) unless (lo..hi).cover?(list.size)
      finals = parsed.front_matter["finals_it"]
      return unless finals.is_a?(Array)

      if finals.size != list.size
        findings.add("E-LESSON-FINALS", "/front_matter/finals_it", "finals_it has #{finals.size} entries and Prova tu has #{list.size} exercises: one for each, null for an open exercise", rule: "count")
        return
      end
      list.each_with_index do |ex, i|
        final = finals[i]
        next unless final.is_a?(String)

        norm = normalize(final)
        next if norm.length < 3

        findings.add("W-LESSON-FINAL-MISSING", "/exercises/#{i}/solution_it", "the final answer of exercise #{ex[:n]} does not appear in its solution", rule: "final-missing-#{i}") unless normalize(ex[:solution_it]).include?(norm)
        findings.add("W-LESSON-FINAL-IN-TRY", "/exercises/#{i}/text_it", "the final answer of exercise #{ex[:n]} appears in its own text", rule: "final-in-try-#{i}") if normalize(ex[:text_it]).include?(norm)
      end
    end

    def normalize(text) = text.to_s.delete("$ ").tr("−", "-")

    # The text S reads, one paragraph or list item at a time (the bullets of a list are not "a bullet
    # list" for the lint). Gulpease is the lesson's own threshold, on the idea and the example.
    def readability(parsed, findings)
      units(parsed).each do |field, text|
        lint = Findings.new
        Readability.lint(text.delete("✓✗"), field: field, role: :text, findings: lint)
        lint.each { |f| findings.add(f.code, f.field, f.message, **f.detail) unless SKIP_IN_LINT.include?(f.code) }
      end
      %w[idea_it example_it].each do |key|
        section = parsed.sections[key] or next
        body = Readability.strip_markup(section.text.gsub(Readability::MATH, " m ").gsub(/^\s*-\s+/, ""))
        sentences = Readability.sentences_of(body)
        n = sentences.sum { |s| Readability.count_words(s) }
        index = Readability.gulpease(body, sentences, n)
        findings.add("W-GULPEASE", "/sections/#{key}", "Gulpease index #{index.round} (below #{rule(:min_gulpease)})", index: index.round) if index && n >= Rules.get(:readability, :min_gulpease_words) && index < rule(:min_gulpease)
      end
    end

    def units(parsed)
      out = []
      parsed.sections.each do |key, section|
        next if %w[try solutions].include?(key) || section.blocks.nil?

        out.concat(block_units(section.blocks, "/sections/#{key}"))
      end
      %w[try solutions].each do |key|
        section = parsed.sections[key] or next
        next unless section.blocks

        out.concat(block_units(section.blocks, "/sections/#{key}"))
      end
      out
    end

    def block_units(blocks, path)
      blocks.each_with_index.flat_map do |b, i|
        if b.type == :p
          [ [ "#{path}/#{i}", b.text ] ]
        else
          b.items.each_with_index.flat_map { |item, j| [ [ "#{path}/#{i}/#{j}", item[:text] ] ] + item[:subs].each_with_index.map { |s, k| [ "#{path}/#{i}/#{j}/#{k}", s ] } }
        end
      end
    end
  end
end
