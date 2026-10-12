# frozen_string_literal: true

module Lessons
  # The blocks of a lesson/2 card (A4): what each type is, what counts as prose, as a visual, as a check, and the
  # walks over a body the checks and the converter need. Semantic checks per type live in lib/lessons/blocks/*.
  module Blocks
    # A "visual" (A3): a diagram, a schema, a procedure, an image or a page, or a cases block with a diagram in one case. Wave 2
    # (WAVE2 1.8): a `source`, a `dialogue`, an `oral` and a `reveal` with options count as a visual, as diagrams do; a plain `reveal` does not.
    VISUAL_TYPES = %w[diagram schema procedure image page source dialogue oral].freeze
    # At most one of these per card (E-CARD-BLOCKS, lesson2.one_per_card): a `reveal` counts only with options.
    ONE_PER_CARD = { "source" => "source", "dialogue" => "dialogue", "oral" => "oral" }.freeze
    CHECK_FREE = %w[text callout math summary mistake table legend more].freeze

    module_function

    def words(text) = Validation::LessonChecks.words(text)

    # Every block of a card, a more block's inner blocks included: [block, inside_more].
    def each_block(card, &block)
      return enum_for(:each_block, card) unless block

      card["blocks"].each do |b|
        yield b, false
        b["blocks"].to_a.each { |inner| yield inner, true } if b["type"] == "more"
      end
    end

    # The strings of a block that count as prose of the card (A3 table): not checks, not the try card, not a more.
    def prose(block)
      case block["type"]
      when "text", "callout" then [ block["text_it"] ]
      when "summary" then block["points_it"].to_a
      when "mistake" then block.values_at("wrong_it", "right_it", "why_it")
      when "example" then block["steps"].to_a.map { |s| s["why_it"] }
      when "procedure" then block["steps"].to_a.map { |s| s["text_it"] }
      when "cases" then block["cases"].to_a.flat_map { |c| c.values_at("text_it", "condition_it", "example_it") }
      when "legend" then block["roles"].to_a.map { |r| r["note_it"] }
      else []
      end.compact
    end

    # Prose of the more blocks of a card (A3: the extra depth).
    def more_prose(card)
      card["blocks"].select { |b| b["type"] == "more" }.flat_map { |m| m["blocks"].to_a.flat_map { |b| prose(b) } }
    end

    def prose_words(card) = prose_of(card).sum { |t| words(t) }

    def prose_of(card) = card["blocks"].flat_map { |b| prose(b) } + [ card["title_it"] ]

    # Diagrams of a block (a cases block holds up to one per case; an example may hold one).
    def diagrams(block)
      case block["type"]
      when "diagram" then [ block["diagram"] ]
      when "schema" then [ block["schema"] ]
      when "cases" then block["cases"].to_a.filter_map { |c| c["diagram"] }
      when "example" then [ block["diagram"] ].compact
      else []
      end
    end

    def visual?(block)
      VISUAL_TYPES.include?(block["type"]) || reveal_with_options?(block) || (block["type"] == "cases" && diagrams(block).any?) || (block["type"] == "example" && false)
    end

    def reveal_with_options?(block) = block["type"] == "reveal" && block["options"].present?

    # The keys of lesson2.one_per_card that a block stands for: "source", "dialogue", "oral" or "reveal_options".
    def single_kind(block) = reveal_with_options?(block) ? "reveal_options" : ONE_PER_CARD[block["type"]]

    # How many diagrams, schemas and procedures a block counts for A3's ceiling (a cases counts each diagram in it).
    def visual_count(block) = visual_count_of(block) + checks(block).count { |c| c["component"] == "select" }

    def visual_count_of(block)
      case block["type"]
      when "diagram", "schema", "procedure", "source", "dialogue", "oral", "image", "page" then 1
      when "reveal" then reveal_with_options?(block) ? 1 : 0
      when "cases", "example" then diagrams(block).size
      else 0
      end
    end

    # The checks a block carries: a check block, the blank of an example step, the checks of a try exercise.
    def checks(block)
      case block["type"]
      when "check" then [ block ]
      when "example" then block["steps"].to_a.filter_map { |s| s["blank"] }
      when "try" then block["exercises"].to_a.flat_map { |e| e["checks"] || [ e["check"] ].compact }
      else []
      end
    end

    # Every _it text that is markup v2 in a block, with its path inside the block and whether a list is allowed.
    # [[path, text, lists_allowed]]
    def markup_fields(block)
      out = []
      add = ->(path, text, lists = false) { out << [ path, text, lists ] if text.is_a?(String) }
      case block["type"]
      when "text" then add.call("text_it", block["text_it"], true)
      when "callout" then add.call("text_it", block["text_it"])
      when "summary" then block["points_it"].to_a.each_with_index { |t, i| add.call("points_it/#{i}", t) }
      when "mistake" then %w[wrong_it right_it why_it].each { |k| add.call(k, block[k]) }
      when "procedure" then block["steps"].to_a.each_with_index { |s, i| add.call("steps/#{i}/text_it", s["text_it"]) }
      when "cases"
        block["cases"].to_a.each_with_index { |c, i| %w[text_it condition_it example_it].each { |k| add.call("cases/#{i}/#{k}", c[k]) } }
      when "legend" then block["roles"].to_a.each_with_index { |r, i| %w[note_it question_it].each { |k| add.call("roles/#{i}/#{k}", r[k]) } }
      when "example"
        add.call("problem_it", block["problem_it"])
        block["steps"].to_a.each_with_index do |s, i|
          add.call("steps/#{i}/do_it", s["do_it"])
          add.call("steps/#{i}/why_it", s["why_it"])
          check_fields(s["blank"], "steps/#{i}/blank", add) if s["blank"]
        end
        add.call("result_it", block["result_it"], true)
      when "check" then check_fields(block, "", add)
      when "source"
        block["parts"].to_a.each_with_index { |part, i| add.call("parts/#{i}/plain_it", part["plain_it"]) }
        block["guide"].to_a.each_with_index { |g, i| add.call("guide/#{i}/note_it", g["note_it"]) }
      when "reveal"
        %w[prompt_it answer_it situation_it real_it].each { |k| add.call(k, block[k]) }
        block["options"].to_a.each_with_index { |o, i| %w[text_it then_it].each { |k| add.call("options/#{i}/#{k}", o[k]) } }
      when "dialogue"
        add.call("title_it", block["title_it"])
        block["lines"].to_a.each_with_index { |l, i| add.call("lines/#{i}/gloss_it", l["gloss_it"]) }
      when "oral"
        add.call("question_it", block["question_it"])
        block["outline"].to_a.each_with_index { |o, i| add.call("outline/#{i}/text_it", o["text_it"]) }
        block["errors"].to_a.each_with_index { |e, i| add.call("errors/#{i}/message_it", e["message_it"]) }
        add.call("model_it", block["model_it"])
      when "try"
        add.call("intro_it", block["intro_it"])
        block["exercises"].to_a.each_with_index do |e, i|
          add.call("exercises/#{i}/text_it", e["text_it"], true)
          add.call("exercises/#{i}/final_it", e["final_it"])
          add.call("exercises/#{i}/solution_it", e["solution_it"], true)
          e["solution_steps"].to_a.each_with_index do |s, k|
            add.call("exercises/#{i}/solution_steps/#{k}/do_it", s["do_it"])
            add.call("exercises/#{i}/solution_steps/#{k}/why_it", s["why_it"])
          end
          if e["checks"] then e["checks"].each_with_index { |ch, k| check_fields(ch, "exercises/#{i}/checks/#{k}", add) }
          elsif e["check"] then check_fields(e["check"], "exercises/#{i}/check", add)
          end
        end
      end
      out
    end

    # ---- the apparatus (WAVE2 1.8, E-LESSON-APPARATUS-WORDS): words open by default beside the 500 words of prose ------------------

    # The words of a block that are open by default and are not prose: a source's text shown first (the plain version, else the quotation),
    # a reveal's prompt (or situation), its options and what each leads to. The back of a reveal, the model of an oral and the legal text
    # behind the plain version are behind a tap. Other families add their branches (dialogue lines, mirror rows, document blocks, glossary).
    def apparatus_words(block)
      case block["type"]
      when "source"
        block["parts"].to_a.sum { |part| words(source_open_text(block, part)) }
      when "reveal"
        texts = [ block["prompt_it"], block["situation_it"] ] + block["options"].to_a.flat_map { |o| [ o["text_it"], o["then_it"] ] }
        texts.compact.sum { |t| words(t) }
      when "dialogue"
        # the lines are open by default unless the transcript starts hidden; the glosses are behind the IT buttons
        block["transcript"] == "hidden" ? 0 : block["lines"].to_a.sum { |l| words(l["text_en"] || l["text_es"]) }
      when "diagram", "schema"
        mirror_words(block["diagram"] || block["schema"])
      else 0
      end
    end

    # The words of a mirror figure's rows (both sides, a piece written joined counts as one word): open by default, so apparatus.
    def mirror_words(diagram)
      return 0 unless diagram.is_a?(Hash) && diagram["type"] == "mirror"

      diagram["rows"].to_a.sum { |row| row.slice("pieces_it", "pieces_en", "pieces_es").values.sum { |pieces| pieces.sum { |p| words(p.delete("+")) } } }
    end

    # Words of originals that are closed by default: the legal words behind a source's plain version.
    def closed_original_words(block)
      return 0 unless block["type"] == "source"

      block["parts"].to_a.sum { |part| source_open_text(block, part) == part["text_it"] ? 0 : words(part["text_it"]) }
    end

    # What a source part shows first: the plain version when there is one and open is not "original", else the quotation.
    def source_open_text(block, part)
      block["open"] != "original" && part["plain_it"] ? part["plain_it"] : part["text_it"]
    end

    def check_fields(check, base, add)
      join = ->(k) { base.empty? ? k : "#{base}/#{k}" }
      %w[prompt_it explain_it answer_format_it input_before input_after].each { |k| add.call(join.call(k), check[k]) }
      check["options"].to_a.each_with_index { |o, i| add.call(join.call("options/#{i}/text_it"), o["text_it"]) }
      %w[left right].each { |side| check[side].to_a.each_with_index { |o, i| add.call(join.call("#{side}/#{i}/text_it"), o["text_it"]) } }
      %w[tiles items].each { |side| check[side].to_a.each_with_index { |o, i| add.call(join.call("#{side}/#{i}/text_it"), o["text_it"]) } }
      check["errors"].to_a.each_with_index { |e, i| add.call(join.call("errors/#{i}/message_it"), e["message_it"]) }
    end
  end
end
