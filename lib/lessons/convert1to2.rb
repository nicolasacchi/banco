# frozen_string_literal: true

module Lessons
  # banco.lesson/1 -> a banco.lesson/2 draft (A15.1). Everything the old lesson says is kept, in cards; nothing is
  # invented: no visual, no check, no schema, no goals and no placeholder text. The draft fails the lint on exactly
  # what the author has to add (E-CARD-NO-VISUAL, E-LESSON-MAP, E-LESSON-CHECKS, goals_it), which is the author's
  # to-do list. What cannot be mapped without loss (a step with no "Perché:", an error with no ✗ and ✓) stays as plain
  # text in its card.
  #
  #   why -> why_it            "L'idea in breve", cut at bold-headed paragraphs and at numbered lists -> idea cards
  #   Esempio svolto           -> example cards (steps "…  Perché: …" -> example steps)
  #   Errori da evitare        -> one mistakes card of mistake blocks (✗ wrong ✓ right, then why)
  #   Prova tu + Soluzioni + finals_it -> one try card (exercises with final_it and solution_it)
  #   Sul libro (the words after the fixed line) -> book_it     In sintesi -> a summary card
  module Convert1to2
    class Refused < StandardError; end

    WHY_MARKER = /\s*\bPerch[ée]\s*:\s*/i

    module_function

    # +source_v1+: the text of a lesson.md in banco.lesson/1; returns the text of a banco.lesson/2 lesson.md.
    def call(source_v1)
      findings = Validation::Findings.new
      parsed = Parser.call(source_v1, findings)
      raise Refused, "the lesson does not parse as banco.lesson/1: #{findings.errors.map(&:message).first(2).join('; ')}" unless parsed&.sections && parsed.exercises

      fm = parsed.front_matter
      secs = parsed.sections
      out = +"---\nschema: banco.lesson/2\n"
      %w[key kind subject].each { |k| out << "#{k}: #{fm[k]}\n" }
      out << "title_it: #{q(fm['title_it'])}\n"
      out << "# goals_it: 1 to 3 lines, each starting with a verb in bold (**Risolvere** ...); the old lesson has none\n"
      out << "skills: #{flow(fm['skills'])}\nuses: #{flow(fm['uses'] || [])}\n"
      out << "refs:\n#{fm['refs'].map { |r| "  - #{ref(r)}\n" }.join}"
      out << "scope: #{fm['scope']}\nminutes: #{fm['minutes']}\ncalculator: #{fm['calculator']}\n"
      out << "why_it: #{q(one_line(secs['why_it'].text))}\n"
      book = secs["book_it"].text.sub(Validation::Rules.get(:lesson, :book_line), "").strip
      out << "book_it: #{q(one_line(book))}\n" unless book.empty?
      out << "---\n"
      out << ideas(secs["idea_it"])
      out << examples(secs["example_it"])
      out << mistakes(secs["mistakes_it"])
      out << try_card(parsed, fm["finals_it"])
      out << summary(secs["summary_it"])
      out
    end

    # ---- cards ---------------------------------------------------------------------------------------

    # The blocks of "L'idea in breve", cut into cards at a bold-headed paragraph and around each numbered list.
    def ideas(section)
      groups = []
      section.blocks.each do |b|
        starts_bold = b.type == :p && b.text.start_with?("**")
        introduced = b.type == :ol && groups.last && groups.last[:blocks].last&.type == :p && groups.last[:blocks].last.text.end_with?(":")
        if groups.empty? || starts_bold || (b.type == :ol && !introduced) || groups.last[:list]
          groups << { blocks: [], list: b.type == :ol }
        end
        groups.last[:list] = true if b.type == :ol
        groups.last[:blocks] << b
      end
      groups.map { |g| "\n## #{title_of(g[:blocks].first)} {idea}\n\n#{text_block(g[:blocks])}\n" }.join
    end

    # Examples: intro paragraphs followed by one numbered list make one example; the rest stays text.
    def examples(section)
      groups = []
      section.blocks.each do |b|
        groups << { intro: [], list: nil } if groups.empty? || groups.last[:list]
        b.type == :ol ? groups.last[:list] = b : groups.last[:intro] << b
      end
      groups.map { |g| example_card(g) }.join
    end

    def example_card(group)
      head = group[:intro].first || group[:list]
      title = title_of(head)
      body = +"\n## #{title} {example}\n\n"
      steps = group[:list] && group[:list].items.map { |i| split_step(item_text(i)) }
      if steps && steps.all?(&:last) && group[:intro].any?
        body << "::: example\n#{kv('problem_it', group[:intro].map(&:source).join("\n\n"))}steps:\n"
        steps.each { |do_it, why| body << "  - do_it: #{q(one_line(do_it))}\n    why_it: #{q(one_line(why))}\n" }
        body << ":::\n"
      else
        body << "#{text_block(group[:intro] + [ group[:list] ].compact)}\n"
      end
      body
    end

    def split_step(text)
      do_it, why = text.split(WHY_MARKER, 2)
      [ do_it.to_s.strip, why&.strip.presence ]
    end

    def mistakes(section)
      mistake_blocks = []
      loose = []
      section.blocks.each do |b|
        items = b.type == :p ? [ { text: b.text, subs: [] } ] : b.items
        items.each do |i|
          parsed = mistake(i)
          parsed ? mistake_blocks << parsed : loose << item_text(i)
        end
      end
      out = +"\n## Errori da evitare {mistakes}\n\n"
      out << "#{loose.map { |t| "- #{one_line(t)}" }.join("\n")}\n\n" if loose.any?
      out << mistake_blocks.map { |m| "::: mistake\n#{m}:::\n" }.join("\n")
      out
    end

    # ✗ wrong ✓ right, then the reason; also across the nested lines of an item. nil when there is no ✗ and ✓.
    def mistake(item)
      whole = ([ item[:text] ] + item[:subs]).join("\n")
      return nil unless whole.include?("✗") && whole.include?("✓")

      after_cross = whole.split("✗", 2).last
      wrong, rest = after_cross.split("✓", 2)
      right, why = split_right(rest.to_s)
      return nil if [ wrong, right ].any? { |t| t.to_s.strip.empty? }

      "#{kv('wrong_it', one_line(wrong))}#{kv('right_it', one_line(right))}#{kv('why_it', one_line(why.to_s.strip.empty? ? right : why))}"
    end

    # The right form is the first formula (or the first sentence); what follows is the reason.
    def split_right(text)
      t = text.strip
      if (m = t.match(/\A(\$[^$]+\$)\s*[.;:,\-–—]?\s*(.*)\z/m))
        [ m[1], m[2] ]
      elsif (m = t.match(/\A(.+?[.!?])\s+(.*)\z/m))
        [ m[1], m[2] ]
      else
        [ t, "" ]
      end
    end

    def try_card(parsed, finals)
      out = +"\n## Prova tu {try}\n\n::: try\n"
      out << kv("intro_it", one_line(parsed.try_intro)) if parsed.try_intro
      out << "exercises:\n"
      parsed.exercises.each_with_index do |ex, i|
        out << "  - #{kv('text_it', ex[:text_it], 4, first: true)}"
        final = finals && finals[i]
        out << kv("final_it", final, 4) if final
        out << kv("solution_it", ex[:solution_it], 4)
      end
      out << ":::\n"
    end

    def summary(section)
      points = section.blocks.flat_map { |b| b.type == :p ? [ b.text ] : b.items.map { |i| item_text(i) } }
      "\n## In sintesi {summary}\n\n::: summary\n#{points.map { |t| "- #{one_line(t)}" }.join("\n")}\n:::\n"
    end

    # ---- text helpers --------------------------------------------------------------------------------

    # The words of a card title: the bold head of a paragraph, else its first words.
    def title_of(block)
      text = block.type == :p ? block.text : block.items.first[:text]
      head = text[/\A\*\*(.+?)\*\*/, 1]
      raw = head || text
      plain = raw.gsub(/\*\*/, "").gsub(/\$[^$]*\$/, "").gsub(/\s+/, " ").strip
      words = plain.split
      title = head ? plain : words.first(6).join(" ")
      title = title.sub(/[\s.,;:!?]+\z/, "")
      title = words.first(6).join(" ").sub(/[\s.,;:!?]+\z/, "") if title.size < 3
      title = "Scheda" if title.size < 3
      title.delete("{}")
    end

    def text_block(blocks) = blocks.map(&:source).join("\n\n")

    def item_text(item) = Parser.item_markup(item)

    def one_line(text) = text.to_s.gsub(/\s*\n\s*/, " ").strip

    # A single-quoted YAML scalar (LaTeX needs no escaping there).
    def q(text) = "'#{text.to_s.gsub("'", "''")}'"

    def flow(list) = "[#{list.join(', ')}]"

    def ref(r) = "{source: #{r['source']}, line: #{r['line']}, fragment: #{q(r['fragment'])}, role: #{r['role']}}"

    # key: value with the value quoted, or a block scalar when it has several lines.
    def kv(key, text, indent = 0, first: false)
      pad = " " * indent
      lead = first ? "" : pad
      if text.to_s.include?("\n")
        body = text.to_s.lines.map { |l| l.chomp.empty? ? "\n" : "#{pad}  #{l.chomp}\n" }.join
        "#{lead}#{key}: |-\n#{body}"
      else
        "#{lead}#{key}: #{q(text)}\n"
      end
    end
  end
end
