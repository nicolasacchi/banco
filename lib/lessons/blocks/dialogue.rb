# frozen_string_literal: true

module Lessons
  module Blocks
    # The `dialogue` block (WAVE2 2.6, T3): a scripted exchange in the target language, every line with its Italian gloss one tap away. The schema
    # (b_dialogue) has made the shape right; these are the rules it cannot hold: one target language for the whole dialogue (text_en or text_es, and
    # a subject that teaches it), every line short enough to be read (E-READ, the target-language set), every speaker real, named once and speaking,
    # voices that differ. The browser side is lesson/blocks/dialogue.js.
    module Dialogue
      TEXT_KEYS = { "text_en" => "en", "text_es" => "es" }.freeze
      TEACHES = { "en" => "english", "es" => "spanish" }.freeze

      module_function

      def rule(key) = Validation::Rules.get(:lesson2, :types, :dialogue, key.to_sym)

      def words(text) = Blocks.words(text)

      def key_of(line) = TEXT_KEYS.keys.find { |k| line[k] }

      def check(block, ctx)
        lines = block["lines"].to_a
        keys = lines.map { |l| key_of(l) }
        lines.each_with_index do |l, i|
          both = TEXT_KEYS.keys.select { |k| l[k] }
          ctx.error("lines/#{i}", "a line is written in one language: text_en or text_es (here #{both.size})", rule: "line-language-#{i}") if both.size != 1
        end
        if keys.compact.uniq.size > 1
          ctx.add("E-LESSON-LANG", "lines", "a dialogue is in one language: #{keys.compact.uniq.join(', ')}", rule: "one-language")
        elsif keys.compact.first
          lang = TEXT_KEYS.fetch(keys.compact.first)
          ctx.add("E-LESSON-LANG", "lines/0/#{keys.compact.first}", "#{keys.compact.first} is not a language this subject teaches", rule: "lang") unless TEACHES[lang] == ctx.subject
        end
        lines.each_with_index do |l, i|
          k = key_of(l)
          next unless k

          n = words(l[k])
          ctx.add("E-READ", "lines/#{i}/#{k}", "a dialogue line has #{n} words (at most #{rule(:line_words)})", rule: "line-words-#{i}") if n > rule(:line_words)
          next unless k == "text_es"

          Words.tilde_warnings(l[k]).each { |w| ctx.add("W-ES-TILDE", "lines/#{i}/#{k}", "the tilde of #{w} is not needed by the stress rule (or sits on the wrong syllable)", rule: "tilde-#{i}-#{w}") }
        end
        speakers(block, lines, ctx)
      end

      def speakers(block, lines, ctx)
        list = block["speakers"].to_a
        ids = list.map { |s| s["id"] }
        ctx.error("speakers", "a speaker id is used twice", rule: "speaker-ids") if ids.uniq.size != ids.size
        names = list.map { |s| s["name"] }
        ctx.error("speakers", "two speakers have the same name", rule: "speaker-names") if names.uniq.size != names.size
        voices = list.filter_map { |s| s["voice"] }
        ctx.error("speakers", "two speakers have the same voice", rule: "speaker-voices") if voices.uniq.size != voices.size
        lines.each_with_index do |l, i|
          ctx.error("lines/#{i}/speaker", "the speaker #{l['speaker'].inspect} is not in speakers", rule: "line-speaker-#{i}") unless ids.include?(l["speaker"])
        end
        ids.each_with_index do |id, k|
          ctx.error("speakers/#{k}", "#{names[k]} says nothing: every speaker has a line", rule: "speaker-silent-#{k}") unless lines.any? { |l| l["speaker"] == id }
        end
        ctx.error("lines", "the dialogue needs a second speaker's line after the first: one voice alone is a monologue", rule: "monologue") if list.size > 1 && lines.map { |l| l["speaker"] }.uniq.size < 2
      end
    end
  end
end
