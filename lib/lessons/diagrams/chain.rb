# frozen_string_literal: true

module Lessons
  module Diagrams
    # chain (WAVE2 2.1, T4b): causes, effects and cycles. Nodes are declared in reading order (a line along its path, a fan as the causes,
    # then the event, then its effects, a ring around its cycle), so a link goes to the next node, or into the event of a fan; "Togli una
    # causa" greys what is left without a causal path from a present cause. The browser twin is lesson/diagrams/graph/chain.js; both run
    # test/fixtures/diagrams/types/chain.json. The words are those of config/locales/lesson_graph.it.yml (key `scene`).
    module Chain
      extend Contract

      DEFAULT_WORD = { "line" => "porta a", "fan" => "quindi", "ring" => "poi" }.freeze

      class << self
        def caps = Validation::Rules.get(:lesson2, :types, :chain)

        def text(key) = I18n.t("lesson_graph.scene.#{key}")

        def static(data, c)
          nodes = data["nodes"]
          ids = nodes.map { |n| n["id"] }
          layout = data["layout"]
          c.map("/nodes", "node ids must be unique", rule: "ids") if ids.uniq.size != ids.size
          nodes.each_with_index do |n, i|
            words = Diagrams.label_words(n["text_it"])
            c.diagram("/nodes/#{i}/text_it", "a node has #{words} words (at most #{caps['node_words']})", rule: "node-words#{i}") if words > caps["node_words"]
            c.diagram("/nodes/#{i}/kind", "a ring has stages only; a line or a fan has none", rule: "stage#{i}") if (n["kind"] == "stage") != (layout == "ring")
          end
          links = data["links"]
          index = ids.each_with_index.to_h
          good = true
          links.each_with_index do |l, i|
            at = "/links/#{i}"
            unless index.key?(l["from"]) && index.key?(l["to"])
              c.map(at, "the link names a node that does not exist", rule: "link-node#{i}")
              good = false
              next
            end
            c.map(at, "a link joins two different nodes", rule: "link-self#{i}") if l["from"] == l["to"]
            c.diagram("#{at}/word", "a link that is not causal carries no word: \"#{text('not_causal')}\" is written on it", rule: "word-not-causal#{i}") if l["causal"] == false && l["word"]
          end
          return unless good

          c.diagram("/links", "at most #{caps['not_causal_links']} links are not causal", rule: "not-causal") if links.count { |l| l["causal"] == false } > caps["not_causal_links"]
          backs = links.each_index.select { |i| links[i]["back"] }
          c.diagram("/links", "at most #{caps['back_links']} link goes back", rule: "backs") if backs.size > caps["back_links"]
          backs.each do |i|
            c.diagram("/links/#{i}/back", "only a line has a link that goes back", rule: "back-layout#{i}") unless layout == "line"
            c.map("/links/#{i}", "a link that goes back runs from a later node to an earlier one", rule: "back-order#{i}") unless index[links[i]["from"]] > index[links[i]["to"]]
          end
          pairs = links.each_index.reject { |i| links[i]["back"] }.map { |i| [ index[links[i]["from"]], index[links[i]["to"]] ] }
          c.map("/links", "the same link is written twice", rule: "link-twice") if pairs.uniq.size != pairs.size
          send("check_#{layout}", data, c, ids, links, index)
          if data["remove"]
            c.diagram("/remove", "a ring has no \"Togli una causa\"", rule: "remove-ring") if layout == "ring"
            c.diagram("/remove", "\"Togli una causa\" needs at least one cause", rule: "remove-causes") unless nodes.any? { |n| n["kind"] == "cause" }
            nodes.each_with_index do |n, i|
              next if n["kind"] == "cause" || n["kind"] == "stage"

              c.map("/nodes/#{i}", "#{n['id']} is an #{n['kind']} with no cause behind it", rule: "no-cause#{i}") unless links.any? { |l| l["to"] == n["id"] && l["causal"] != false && !l["back"] }
            end
          end
        end

        # A line: the links of the path join each node to the next one, in order.
        def check_line(data, c, ids, links, index)
          wanted = (0...(ids.size - 1)).map { |i| [ i, i + 1 ] }
          have = links.reject { |l| l["back"] }.map { |l| [ index[l["from"]], index[l["to"]] ] }.sort
          c.map("/links", "a line is one path: each node is linked to the next, in the order the nodes are written", rule: "line-path") unless have == wanted
          c.diagram("/nodes", "a line has at most one event", rule: "line-event") if data["nodes"].count { |n| n["kind"] == "event" } > 1
        end

        # A fan: the causes, then the one event, then its effects; a link goes to the next node or into the event.
        def check_fan(data, c, ids, links, index)
          nodes = data["nodes"]
          events = nodes.each_index.select { |i| nodes[i]["kind"] == "event" }
          unless events.size == 1
            c.diagram("/nodes", "a fan has exactly one event (here #{events.size})", rule: "fan-event")
            return
          end
          e = events.first
          nodes.each_with_index do |n, i|
            c.diagram("/nodes/#{i}/kind", "in a fan the nodes before the event are causes and the ones after it are effects", rule: "fan-order#{i}") if i < e && n["kind"] != "cause" || i > e && n["kind"] != "effect"
          end
          into = []
          links.each_with_index do |l, i|
            from = index[l["from"]]
            to = index[l["to"]]
            if to == e
              into << l
            elsif to != from + 1
              c.map("/links/#{i}", "in a fan a link goes to the next node or into the event", rule: "fan-link#{i}")
            end
          end
          causal = into.select { |l| l["causal"] != false }
          c.diagram("/links", "a fan needs at least 2 causal links into the event (here #{causal.size})", rule: "fan-in") if causal.size < 2
          c.diagram("/links", "the links into the event use the same word", rule: "fan-word") if causal.map { |l| l["word"] || DEFAULT_WORD["fan"] }.uniq.size > 1
        end

        # A ring: every node is linked to the next one, and the last to the first.
        def check_ring(data, c, ids, links, index)
          wanted = (0...ids.size).map { |i| [ i, (i + 1) % ids.size ] }.sort
          have = links.map { |l| [ index[l["from"]], index[l["to"]] ] }.sort
          c.map("/links", "a ring is one cycle through every node, in the order the nodes are written", rule: "ring-cycle") unless have == wanted
          c.diagram("/links", "a ring has only causal links", rule: "ring-causal") if links.any? { |l| l["causal"] == false }
        end

        def state(data, c, path)
          return unless data["show"]

          ids = data["nodes"].map { |n| n["id"] }
          data["show"].each_with_index { |s, i| c.map("#{path}/show/#{i}", "show names a node that does not exist", rule: "show#{path}/#{i}") unless ids.include?(s) }
        end

        # ---- what the browser is told -------------------------------------------------------------------

        def served(data, mode: :student)
          return StudentBody.diagram(data) unless mode == :select

          nodes = data["nodes"].map { |n| { "id" => n["id"], "kind" => "stage", "text_it" => "·" } }
          { "type" => "chain", "alt_it" => "Schema con #{nodes.size} caselle collegate da frecce.", "layout" => data["layout"], "nodes" => nodes,
            "links" => data["links"].map { |l| l.slice("from", "to", "back") } }
        end

        def targets(data, set)
          raise ArgumentError, "chain has no select set #{set.inspect}" unless set.to_s == "nodes"

          data["nodes"].map { |n| n["id"] }
        end

        # ---- what a state prints ------------------------------------------------------------------------

        def word_of(data, link)
          link["causal"] == false ? text("not_causal") : (link["word"] || DEFAULT_WORD[data["layout"]])
        end

        # The nodes still alive when the student has taken the causes in +removed+ away: a present cause, or a node with a causal link
        # from an alive one (back links are left out: the acyclic part only).
        def alive(data, removed)
          alive = data["nodes"].select { |n| n["kind"] == "cause" && !removed.include?(n["id"]) }.map { |n| n["id"] }
          loop do
            more = data["links"].select { |l| l["causal"] != false && !l["back"] && alive.include?(l["from"]) && !alive.include?(l["to"]) && !removed.include?(l["to"]) }.map { |l| l["to"] }
            break if more.empty?

            alive |= more
          end
          alive
        end

        def shown(data, state)
          eff = Diagrams.effective_states(data)
          show = (eff.empty? ? data : eff.fetch([ state, eff.size - 1 ].min))["show"]
          show ? data["nodes"].select { |n| show.include?(n["id"]) } : data["nodes"]
        end

        def plain(t) = t.to_s.delete("$")

        def list_it(items) = items.size <= 1 ? items.join : "#{items[0..-2].join(', ')} e #{items.last}"

        def describe(data, state: 0, removed: [])
          nodes = shown(data, state)
          ids = nodes.map { |n| n["id"] }
          by_id = data["nodes"].to_h { |n| [ n["id"], n ] }
          kind = { "line" => "Una catena di cause.", "fan" => "Tante cause per un fatto solo.", "ring" => "Un giro che ricomincia." }.fetch(data["layout"])
          parts = [ kind ]
          data["links"].each do |l|
            next unless ids.include?(l["from"]) && ids.include?(l["to"])

            from = plain(by_id[l["from"]]["text_it"])
            to = plain(by_id[l["to"]]["text_it"])
            word = word_of(data, l)
            parts << if l["causal"] == false then "#{from}: #{word}, non è una causa di #{to}."
            elsif word == "perché" then "#{to} perché #{from}."
            elsif l["back"] then "Poi si torna indietro: #{from} #{word} #{to}."
            else "#{from} #{word} #{to}."
            end
          end
          if nodes.size == 1 || data["links"].none? { |l| ids.include?(l["from"]) && ids.include?(l["to"]) }
            parts << "#{list_it(nodes.map { |n| plain(n['text_it']) })}."
          end
          if data["remove"] && removed.any?
            alive = alive(data, removed)
            grey = nodes.reject { |n| alive.include?(n["id"]) || removed.include?(n["id"]) }
            parts << "#{text('removed_now')}: #{list_it(removed.map { |r| plain(by_id[r]["text_it"]) })}."
            parts << (grey.any? ? "#{text('grey_tag').capitalize}: #{list_it(grey.map { |n| plain(n['text_it']) })}." : text("nothing_grey"))
            parts << text("hypothesis")
          end
          parts.join(" ")
        end

        def printed(data, state)
          out = shown_all(data).map { |n| n["text_it"] }
          data["links"].each { |l| out << word_of(data, l) }
          out << (Diagrams.effective_states(data)[state] || {})["op_it"]
          out.push(text("hypothesis"), text("nothing_grey"), text("grey_tag"), text("removed")) if data["remove"]
          out << describe(data, state: state)
          out.compact.map(&:to_s).reject(&:empty?).uniq
        end

        def shown_all(data) = data["nodes"]
      end
    end
  end
end
