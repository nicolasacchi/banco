# frozen_string_literal: true

require "digest"

module Diagnosis
  # Serve-time re-keying (X-01). When an instance is served, the order of its
  # choice options, ordering elements and both matching columns is drawn from the
  # run's seed, and every shown element gets a fresh id in shown order (o1..oN for
  # options, e1..eN for ordering elements, l1..lN and r1..rN for matching). The
  # stored instance is never changed. What the browser sees carries no trace of
  # the stored order, so the position of an element says nothing about the key.
  #
  # An ordering that would be shown equal to the key, to its reverse or to its own
  # stored listing is drawn again; so is a matching whose left or right column
  # keeps its stored order, or whose rows line up with the pairs of the key.
  #
  # The result carries the shown display, the id map {shown id => stored id} (the
  # grader undoes the shuffle with it) and the shown order (stored ids, in shown
  # order, per column). The map and the order are logged in item_served and never
  # serialized to the browser. Pure: same input, same output.
  module Rekey
    MAX_REDRAWS = 200

    Result = Data.define(:display, :id_map, :shown_order)

    module_function

    # display: the stored display (string keys); component: the item's component;
    # answer: the stored key; seed: any string (run salt, serve, instance).
    def call(display:, component:, answer:, seed:)
      case component.to_s
      when "choice" then choice(display, seed)
      when "ordering" then ordering(display, answer, seed)
      when "matching" then matching(display, answer, seed)
      else Result.new(display: display, id_map: {}, shown_order: {})
      end
    end

    # A testlet: each sub item is re-keyed on its own, with a seed of its own.
    # sub_items: [{"id"=>, "component"=>, "display"=>, "answer"=>}]
    def testlet(sub_items, seed:)
      shown = []
      map = {}
      order = {}
      sub_items.each do |sub|
        r = call(display: sub["display"], component: sub["component"], answer: sub["answer"], seed: "#{seed}|#{sub['id']}")
        shown << { "id" => sub["id"], "display" => r.display }
        map[sub["id"]] = r.id_map
        order[sub["id"]] = r.shown_order
      end
      Result.new(display: { "sub_items" => shown }, id_map: map, shown_order: order)
    end

    # Rebuilds the shown display from the stored one and a logged shown order, so
    # a page that is asked for again shows exactly what was shown the first time.
    def replay(display:, component:, shown_order:)
      case component.to_s
      when "choice" then apply_columns(display, "options" => [ "o", shown_order["options"] ])
      when "ordering" then apply_columns(display, "elements" => [ "e", shown_order["elements"] ])
      when "matching" then apply_columns(display, "left" => [ "l", shown_order["left"] ], "right" => [ "r", shown_order["right"] ])
      else display
      end
    end

    def rng(seed)
      Random.new(Digest::SHA256.hexdigest(seed.to_s)[0, 16].to_i(16))
    end

    def choice(display, seed)
      ids = Array(display["options"]).map { |o| o["id"] }
      build(display, "options" => [ "o", ids.shuffle(random: rng(seed)) ])
    end

    def ordering(display, answer, seed)
      stored = Array(display["elements"]).map { |e| e["id"] }
      key = Array(answer).map(&:to_s)
      shown = draw(stored, rng(seed)) do |candidate|
        candidate == key || candidate == key.reverse || candidate == stored
      end
      build(display, "elements" => [ "e", shown ])
    end

    def matching(display, answer, seed)
      left = Array(display["left"]).map { |e| e["id"] }
      right = Array(display["right"]).map { |e| e["id"] }
      pairs = answer.is_a?(Hash) ? answer.to_h { |l, r| [ l.to_s, r.to_s ] } : {}
      random = rng(seed)
      shown_left = draw(left, random) { |candidate| candidate == left }
      shown_right = draw(right, random) do |candidate|
        candidate == right || shown_left.each_with_index.all? { |l, i| pairs[l] == candidate[i] }
      end
      build(display, "left" => [ "l", shown_left ], "right" => [ "r", shown_right ])
    end

    # A shuffle of +ids+ that the block does not reject. Lists of fewer than three
    # cannot avoid every pattern: after MAX_REDRAWS the last draw stands.
    def draw(ids, random)
      candidate = ids.shuffle(random: random)
      MAX_REDRAWS.times do
        return candidate unless yield(candidate)

        candidate = ids.shuffle(random: random)
      end
      candidate
    end

    def build(display, columns)
      id_map = {}
      shown_order = {}
      columns.each do |name, (prefix, stored_ids)|
        shown_order[name] = stored_ids
        stored_ids.each_with_index { |sid, i| id_map["#{prefix}#{i + 1}"] = sid }
      end
      Result.new(display: apply_columns(display, columns), id_map: id_map, shown_order: shown_order)
    end

    def apply_columns(display, columns)
      out = display.dup
      columns.each do |name, (prefix, stored_ids)|
        by_id = Array(display[name]).to_h { |e| [ e["id"], e ] }
        out[name] = stored_ids.each_with_index.map { |sid, i| by_id.fetch(sid).merge("id" => "#{prefix}#{i + 1}") }
      end
      out
    end
  end
end
