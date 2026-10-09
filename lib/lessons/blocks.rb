# frozen_string_literal: true

module Lessons
  # The blocks of a lesson/2 card (A4): what each type is, what counts as prose, as a visual, as a check, and the
  # walks over a body the checks and the converter need. Semantic checks per type live in lib/lessons/blocks/*.
  module Blocks
    # A "visual" (A3): a diagram, a schema, a procedure, an image or a page, or a cases block with a diagram in one case.
    VISUAL_TYPES = %w[diagram schema procedure image page].freeze
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
      VISUAL_TYPES.include?(block["type"]) || (block["type"] == "cases" && diagrams(block).any?) || (block["type"] == "example" && false)
    end

    # How many diagrams, schemas and procedures a block counts for A3's ceiling (a cases counts each diagram in it).
    def visual_count(block)
      case block["type"]
      when "diagram", "schema", "procedure" then 1
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

    def check_fields(check, base, add)
      join = ->(k) { base.empty? ? k : "#{base}/#{k}" }
      %w[prompt_it explain_it answer_format_it input_before input_after].each { |k| add.call(join.call(k), check[k]) }
      check["options"].to_a.each_with_index { |o, i| add.call(join.call("options/#{i}/text_it"), o["text_it"]) }
      %w[left right].each { |side| check[side].to_a.each_with_index { |o, i| add.call(join.call("#{side}/#{i}/text_it"), o["text_it"]) } }
      check["errors"].to_a.each_with_index { |e, i| add.call(join.call("errors/#{i}/message_it"), e["message_it"]) }
    end
  end
end
