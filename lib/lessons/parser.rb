# frozen_string_literal: true

require "yaml"

module Lessons
  # lesson.md -> the parsed body of banco.lesson/1 (A2.1). The source is a front matter between two
  # lines "---" (YAML.safe_load: no aliases, no custom tags) and exactly eight "## " sections.
  # Everything refused here is E-LESSON-PARSE, E-LESSON-SECTIONS, E-LESSON-MARKUP, E-LESSON-EXERCISES
  # or an E-SCHEMA of the front matter; the limits (words, bold, pages, ...) are Validation::LessonChecks.
  module Parser
    # [body key, heading]. try and solutions are not strings of the body: they become exercises.
    SECTIONS = [
      [ "why_it", "Perché ti serve" ], [ "idea_it", "L'idea in breve" ], [ "example_it", "Esempio svolto" ],
      [ "mistakes_it", "Errori da evitare" ], [ "try", "Prova tu" ], [ "solutions", "Soluzioni" ],
      [ "book_it", "Sul libro" ], [ "summary_it", "In sintesi" ]
    ].freeze
    TITLES = SECTIONS.map(&:last).freeze

    # sections: {key => Section}; body: the banco.lesson/1 hash, or nil when anything above was refused;
    # exercises: [{n:, text_it:, solution_it:}] as far as they were read (nil when the structure failed).
    Parsed = Struct.new(:front_matter, :body, :sections, :body_text, :exercises, :try_intro, keyword_init: true)
    Section = Struct.new(:key, :title, :text, :blocks, :line, keyword_init: true)

    module_function

    # The source as the server stores it: LF line ends, NFC.
    def normalize(md) = md.to_s.dup.force_encoding(Encoding::UTF_8).gsub(/\r\n?/, "\n").unicode_normalize(:nfc)

    # Returns Parsed, or nil when there is no front matter to speak of (the finding says why).
    def call(md, findings)
      source = normalize(md)
      return Parser2.call(source, findings) if Parser2.schema2?(source) # banco.lesson/2: cards, see Lessons::Parser2

      unless source.valid_encoding?
        findings.add("E-LESSON-PARSE", "/", "lesson.md is not valid UTF-8", rule: "encoding")
        return nil
      end
      front, body_start = front_matter(source, findings)
      return nil unless front

      schema_ok = front_matter_schema(front, findings)
      key_consistent(front, findings)
      lines = source.split("\n", -1)
      body_text = lines.drop(body_start - 1).join("\n")
      sections = split_sections(lines, body_start, findings)
      parsed = Parsed.new(front_matter: front, sections: sections, body_text: body_text)
      read_markup(parsed, findings)
      read_exercises(parsed, findings)
      parsed.body = build_body(parsed) if schema_ok && !findings.any_error? && parsed.exercises
      parsed
    end

    # [hash, line number of the first line after the closing ---] or [nil, nil].
    def front_matter(source, findings)
      lines = source.split("\n", -1)
      unless lines.first.to_s.rstrip == "---"
        findings.add("E-LESSON-PARSE", "/front_matter", "lesson.md must start with a line --- and a front matter", rule: "no_front_matter")
        return [ nil, nil ]
      end
      close = lines.each_index.find { |i| i.positive? && lines[i].rstrip == "---" }
      unless close
        findings.add("E-LESSON-PARSE", "/front_matter", "the front matter is not closed by a second line ---", rule: "unclosed")
        return [ nil, nil ]
      end
      begin
        data = YAML.safe_load(lines[1...close].join("\n"), permitted_classes: [], aliases: false)
      rescue Psych::Exception, ArgumentError => e
        findings.add("E-LESSON-PARSE", "/front_matter", "the front matter is not valid YAML: #{e.message.lines.first.to_s.strip.first(160)} (write LaTeX in single quotes)", rule: "yaml")
        return [ nil, nil ]
      end
      unless data.is_a?(Hash)
        findings.add("E-LESSON-PARSE", "/front_matter", "the front matter must be a mapping of keys and values", rule: "not_a_mapping")
        return [ nil, nil ]
      end
      [ data, close + 2 ]
    end

    def front_matter_schema(front, findings)
      errors = Banco::Schemas.validate_front_matter(front).first(12)
      errors.each { |e| findings.add("E-SCHEMA", e.field, e.message, rule: "front_matter") }
      errors.empty?
    end

    def key_consistent(front, findings)
      key = front["key"].to_s
      kind, subject, = key.split(".", 3)
      return unless key.match?(/\A(ripasso|ponte|lezione)\.[a-z_]+\./)

      findings.add("E-LESSON-PARSE", "/front_matter/kind", "kind is #{front['kind'].inspect} but the key #{key} starts with #{kind}", rule: "kind") if front["kind"] != kind
      findings.add("E-LESSON-PARSE", "/front_matter/subject", "subject is #{front['subject'].inspect} but the key #{key} is for #{subject}", rule: "subject") if front["subject"] != subject
    end

    # Splits the body at lines "## "; the headings must be the eight, in order.
    def split_sections(lines, body_start, findings)
      found = []
      lines.each_with_index do |line, i|
        next if i + 1 < body_start

        if line.start_with?("## ")
          found << { title: line[3..].strip, line: i + 2, rows: [] }
        elsif found.empty?
          findings.add("E-LESSON-SECTIONS", "/sections", "text before the first ## heading (line #{i + 1})", rule: "before_first") unless line.strip.empty?
        else
          found.last[:rows] << line
        end
      end
      titles = found.map { |f| f[:title] }
      unless titles == TITLES
        missing = TITLES - titles
        extra = titles - TITLES
        why = []
        why << "missing: #{missing.join(', ')}" if missing.any?
        why << "not expected: #{extra.join(', ')}" if extra.any?
        why << "out of order or repeated" if missing.empty? && extra.empty?
        findings.add("E-LESSON-SECTIONS", "/sections", "the sections must be, in order: #{TITLES.join(' | ')} (#{why.join('; ')})", rule: "headings", titles: titles)
      end
      found.each_with_object({}) do |f, h|
        index = TITLES.index(f[:title]) or next
        key = SECTIONS[index].first
        next if h.key?(key)

        rows = f[:rows]
        lead = rows.index { |r| !r.strip.empty? } || 0
        text = rows.drop(lead).join("\n").rstrip
        findings.add("E-LESSON-SECTIONS", "/sections/#{key}", "the section #{f[:title]} is empty", rule: "empty-#{key}") if text.empty?
        h[key] = Section.new(key: key, title: f[:title], text: text, blocks: nil, line: f[:line] + lead)
      end
    end

    def read_markup(parsed, findings)
      parsed.sections.each_value do |section|
        next if section.text.empty?

        begin
          section.blocks = Markup.raw_blocks(section.text, line_offset: section.line)
        rescue Markup::Refused => e
          findings.add("E-LESSON-MARKUP", "/sections/#{section.key}", "line #{e.line}: #{e.construct}", rule: "line-#{e.line}", line: e.line, construct: e.construct)
        end
      end
    end

    # Prova tu: optional intro paragraphs, then one ordered list numbered 1..N. Soluzioni: one ordered list, same N.
    def read_exercises(parsed, findings)
      try = parsed.sections["try"]
      solutions = parsed.sections["solutions"]
      return unless try&.blocks && solutions&.blocks

      intro = try.blocks.take_while { |b| b.type == :p }
      lists = try.blocks.drop(intro.size)
      list = single_numbered_list(lists, "Prova tu", findings, "/sections/try") or return
      sol_list = single_numbered_list(solutions.blocks, "Soluzioni", findings, "/sections/solutions") or return
      if sol_list.items.size != list.items.size
        findings.add("E-LESSON-EXERCISES", "/sections/solutions", "Prova tu has #{list.items.size} exercises and Soluzioni has #{sol_list.items.size}: one solution for each", rule: "count")
        return
      end
      parsed.try_intro = intro.empty? ? nil : intro.map(&:source).join("\n\n")
      parsed.exercises = list.items.zip(sol_list.items).map do |e, s|
        { n: e[:n], text_it: item_markup(e), solution_it: item_markup(s) }
      end
    end

    def single_numbered_list(blocks, title, findings, field)
      lists = blocks.select { |b| b.type == :ol }
      if blocks.size != 1 || lists.size != 1
        findings.add("E-LESSON-EXERCISES", field, "#{title} must be exactly one numbered list (1. 2. 3. ...)#{title == 'Prova tu' ? ', optionally after introduction paragraphs' : ''}", rule: "shape-#{title}")
        return nil
      end
      numbers = lists.first.items.map { |i| i[:n] }
      unless numbers == (1..numbers.size).to_a
        findings.add("E-LESSON-EXERCISES", field, "#{title} must be numbered 1, 2, 3, ... in order (found #{numbers.join(', ')})", rule: "numbering-#{title}")
        return nil
      end
      lists.first
    end

    # An item with its nested lines: the text, then the nested lines as a list after a blank line.
    def item_markup(item)
      return item[:text] if item[:subs].empty?

      "#{item[:text]}\n\n#{item[:subs].map { |s| "- #{s}" }.join("\n")}"
    end

    def build_body(parsed)
      fm = parsed.front_matter
      sections = parsed.sections
      finals = fm["finals_it"]
      {
        "schema" => "banco.lesson/1", "schema_version" => 1,
        "key" => fm["key"], "kind" => fm["kind"], "subject" => fm["subject"], "title_it" => fm["title_it"],
        "skills" => fm["skills"], "uses" => fm["uses"] || [], "refs" => fm["refs"],
        "scope" => fm["scope"], "minutes" => fm["minutes"], "calculator" => fm["calculator"],
        "sections" => %w[why_it idea_it example_it mistakes_it book_it summary_it].to_h { |k| [ k, sections.fetch(k).text ] },
        "try_intro_it" => parsed.try_intro,
        "exercises" => parsed.exercises.each_with_index.map do |ex, i|
          { "n" => ex[:n], "text_it" => ex[:text_it], "solution_it" => ex[:solution_it], "final_it" => finals[i] }
        end
      }
    end
  end
end
