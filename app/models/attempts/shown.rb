module Attempts
  # What a serve showed (a PracticeServe or an ItemServed): the stored instance, the shown order and the id map the serve logged, and the
  # readings that need them: the display as the student got it, the answer in words, the row a comment anchor points at. Pure reads.
  class Shown
    # the column of the display, the prefix of its shown ids and the label of the anchor segment, by component: what the page numbers (`data-comment-anchor`)
    ANCHOR_COLUMNS = { "choice" => %w[options o option], "ordering" => %w[elements e row], "matching" => %w[left l row] }.freeze
    ANCHOR_SEGMENT = /\A(?:row|option):\d+\z/

    attr_reader :body, :component, :stored, :answer, :shown_order, :id_map

    def initialize(serve)
      instance = serve.item_instance
      @body = JSON.parse(instance.item_revision.body_json)
      @component = @body["component"].to_s
      @stored = JSON.parse(instance.display_json)
      @answer = JSON.parse(instance.answer_json)
      @shown_order = hash_of(serve.shown_order_json)
      @id_map = hash_of(serve.id_map_json)
    end

    # The display the student got: the stored one in the shown order, the shown ids (o1.., e1.., l1.. and r1..).
    def display
      Diagnosis::Rekey.replay(display: stored, component: component, shown_order: shown_order)
    rescue NoMethodError, KeyError
      stored # a serve that logged no shown order for a shuffled component: the stored display is all there is
    end

    # The raw answer in words: shown ids turned back into the texts the student saw, as the search's answer documents do.
    def words(raw)
      Diagnosis::AnswerText.words(component, raw, ->(id) { texts[unmap(id)] || id.to_s }).to_s
    rescue JSON::ParserError, NoMethodError, TypeError
      raw.to_s
    end

    # The row an anchor segment (`row:N`, `option:N`: the Nth of the shown column, 1-based) points at, resolved through the shown order:
    # the shown id, the stored id and the text, and what the try did with it. nil when the anchor names no row or option;
    # resolved: false when it does and this item has no such row.
    def anchor_row(anchor, raw)
      segment = anchor.to_s.split("/").reverse.find { |s| s.match?(ANCHOR_SEGMENT) } or return nil
      label, n = segment.split(":")
      n = n.to_i
      column, prefix, expected = ANCHOR_COLUMNS[component]
      return { segment: segment, n: n, resolved: false } unless column && label == expected

      order = shown_order[column].presence
      stored_id = order ? order[n - 1] : Array(stored[column])[n - 1]&.fetch("id", nil)
      return { segment: segment, n: n, column: column, resolved: false } unless stored_id

      shown_id = order ? "#{prefix}#{n}" : stored_id
      out = { segment: segment, n: n, column: column, shown_id: shown_id, stored_id: stored_id, text: texts[stored_id], resolved: true }
      out.merge(given_of(shown_id, stored_id, raw))
    end

    private

    def hash_of(json)
      parsed = json.present? ? JSON.parse(json) : {}
      parsed.is_a?(Hash) ? parsed : {}
    end

    def texts = @texts ||= %w[options elements left right].flat_map { |k| Array(stored[k]) }.to_h { |e| [ e["id"], e["text"] ] }

    def unmap(id) = id_map.fetch(id.to_s, id.to_s)

    # What the try did with the row: a choice, whether the option was picked and whether it is the key; an ordering, where the student put
    # the element and where the key has it; a matching, the right the student paired with the row and the key's.
    def given_of(shown_id, stored_id, raw)
      case component
      when "choice"
        { chosen: raw == shown_id, is_key: answer == stored_id }
      when "ordering"
        placed = Array(JSON.parse(raw)).index(shown_id)
        { given_position: placed && placed + 1, key_position: Array(answer).index(stored_id)&.+(1) }.compact
      when "matching"
        pair = JSON.parse(raw)[shown_id].presence
        { given_text: pair && texts[unmap(pair)], key_text: texts[answer.to_h[stored_id]] }.compact
      else {}
      end
    rescue JSON::ParserError, NoMethodError, TypeError
      {}
    end
  end
end
