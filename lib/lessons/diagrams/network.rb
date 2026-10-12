# frozen_string_literal: true

module Lessons
  module Diagrams
    # network (WAVE2 2.1, T4b): typed, directed relations between actors. The checks the schema cannot make (ids, edges between declared
    # nodes in each effective state, no arrow to a hidden node, the shape of each layout), the projection the student's browser gets, the
    # select targets in reading order and the strings a state prints (L4). The browser twin is lesson/diagrams/graph/network.js; both run
    # test/fixtures/diagrams/types/network.json. The words are those of config/locales/lesson_graph.it.yml (key `scene`).
    module Network
      extend Contract

      EVERYONE = "everyone"

      class << self
        def kinds = Lessons::VettedData.table("network/kinds").fetch("kinds")

        def what = Lessons::VettedData.table("network/kinds").fetch("what")

        def caps = Validation::Rules.get(:lesson2, :types, :network)

        def text(key) = I18n.t("lesson_graph.scene.#{key}")

        def ids(data) = data["nodes"].map { |n| n["id"] }

        # Every id an arrow may name: the nodes, and the crowd when `everyone`.
        def arrow_ids(data) = ids(data) + (data["everyone"] ? [ EVERYONE ] : [])

        def static(data, c)
          declared = ids(data)
          n = declared.size
          c.map("/nodes", "node ids must be unique", rule: "ids") if declared.uniq.size != n
          c.map("/nodes", "the id #{EVERYONE} is kept for the node \"tutti gli altri\"", rule: "everyone-id") if data["everyone"] && declared.include?(EVERYONE)
          check_layout(data, c, declared)
          data["nodes"].each_with_index do |node, i|
            at = "/nodes/#{i}"
            c.role("#{at}/role", node["role"]) if node["role"]
            c.add("E-LESSON-ICON", "#{at}/icon", "#{node['icon']} is not an icon of #{c.subject} (config/banco/icons.yml)", rule: "icon#{at}") if node["icon"] && !Lessons::Icons.allowed?(c.subject, node["icon"])
            words(c, "#{at}/label_it", node["label_it"], caps["label_words"], "a label")
            words(c, "#{at}/note_it", node["note_it"], caps["note_words"], "a note") if node["note_it"]
            words(c, "#{at}/badge_it", node["badge_it"], caps["badge_words"], "a badge") if node["badge_it"]
          end
        end

        def state(data, c, path)
          hidden = Array(data["hide"])
          ids = arrow_ids(data)
          declared = self.ids(data)
          hidden.each_with_index { |h, i| c.map("#{path}/hide/#{i}", "a hidden id is not a node", rule: "hide#{path}/#{i}") unless ids.include?(h) }
          seen = {}
          Array(data["edges"]).each_with_index do |e, i|
            at = "#{path}/edges/#{i}"
            unless ids.include?(e["from"]) && ids.include?(e["to"])
              c.map(at, "the arrow names a node that does not exist", rule: "edge-node#{at}")
              next
            end
            c.map(at, "an arrow joins two different nodes", rule: "edge-self#{at}") if e["from"] == e["to"]
            c.map(at, "an arrow cannot reach a hidden node", rule: "edge-hidden#{at}") if hidden.include?(e["from"]) || hidden.include?(e["to"])
            key = [ e["from"], e["to"], e["kind"] ]
            c.map(at, "the same arrow is written twice", rule: "edge-twice#{at}") if seen[key]
            seen[key] = true
            words(c, "#{at}/label_it", e["label_it"], caps["label_words"], "a label") if e["label_it"]
          end
          Array(data["holds"]).each_with_index do |h, i|
            at = "#{path}/holds/#{i}"
            c.map("#{at}/node", "holds names a node that does not exist", rule: "hold-node#{at}") unless declared.include?(h["node"])
            c.map("#{at}/node", "a hidden node holds nothing", rule: "hold-hidden#{at}") if hidden.include?(h["node"])
            h["items_it"].each_with_index { |item, k| words(c, "#{at}/items_it/#{k}", item, caps["label_words"], "an item") }
          end
          Array(data["badges"]).each_with_index do |b, i|
            c.map("#{path}/badges/#{i}/node", "a badge names a node that does not exist", rule: "badge-node#{path}/#{i}") unless declared.include?(b["node"])
          end
        end

        def check_layout(data, c, declared)
          n = declared.size
          case data["layout"]
          when "pair" then c.diagram("/nodes", "a pair has exactly 2 nodes (here #{n})", rule: "pair") unless n == 2
          when "triangle" then c.diagram("/nodes", "a triangle has exactly 3 nodes (here #{n})", rule: "triangle") unless n == 3
          when "hub"
            if data["centre"].nil? then c.diagram("/centre", "a hub names its centre", rule: "centre")
            elsif !declared.include?(data["centre"]) then c.map("/centre", "the centre is not a node", rule: "centre")
            elsif n < 3 then c.diagram("/nodes", "a hub has a centre and at least 2 more nodes", rule: "hub-size")
            end
          when "fan"
            if data["into"].nil? then c.diagram("/into", "a fan names the node everything flows into", rule: "into")
            elsif !declared.include?(data["into"]) then c.map("/into", "into is not a node", rule: "into")
            elsif n < 3 then c.diagram("/nodes", "a fan has a target and at least 2 sources", rule: "fan-size")
            else
              sources = Array(data["edges"]).select { |e| e["to"] == data["into"] }.map { |e| e["from"] }.uniq
              c.diagram("/edges", "a fan needs at least 2 arrows into #{data['into']} (here #{sources.size})", rule: "fan-in") if sources.size < 2
            end
          end
          c.diagram("/centre", "centre is for the hub layout only", rule: "centre-only") if data["layout"] != "hub" && data.key?("centre")
          c.diagram("/into", "into is for the fan layout only", rule: "into-only") if data["layout"] != "fan" && data.key?("into")
          c.diagram("/filter", "the kind chips are for the hub layout only", rule: "filter-only") if data["filter"] && data["layout"] != "hub"
        end

        def words(c, path, text, max, what)
          n = Diagrams.label_words(text)
          c.diagram(path, "#{what} has #{n} words (at most #{max})", rule: "words#{path}") if n > max
        end

        # ---- what the browser is told -------------------------------------------------------------------

        # :student, :teacher: the whitelist projection of the diagram (states merged). :select: the figure of a select check, with no
        # label, note, badge, icon, role, kind or word, so that the picture alone is left (L3).
        def served(data, mode: :student)
          return StudentBody.diagram(data) unless mode == :select

          neutral = ->(h) { h.merge("kind" => "owes").except("label_it", "what") }
          nodes = data["nodes"].each_with_index.map { |_n, i| { "id" => data["nodes"][i]["id"], "label_it" => "·" } }
          out = { "type" => "network", "alt_it" => "Schema con #{nodes.size} caselle collegate da frecce.", "layout" => data["layout"], "nodes" => nodes,
                  "edges" => Array(Diagrams.effective_states(data).first&.fetch("edges", nil) || data["edges"]).map { |e| neutral.call(e) } }
          out["centre"] = data["centre"] if data["centre"]
          out["into"] = data["into"] if data["into"]
          out
        end

        # The stored ids of a select set in reading order: nodes as declared, arrows as written in the first state.
        def targets(data, set)
          case set.to_s
          when "nodes" then ids(data)
          when "edges" then edges_of(data, 0).map { |e| edge_key(e) }
          else raise ArgumentError, "network has no select set #{set.inspect}"
          end
        end

        # The words a teacher reads for a target, and the words the figure's alt text must not say when the target is an answer (L3):
        # a node by its label, an arrow by the labels of its two ends.
        def target_names(data, set)
          label = ->(id) { data["nodes"].find { |n| n["id"] == id }&.fetch("label_it", nil).to_s.gsub(/[*_$`]/, "").strip }
          case set.to_s
          when "nodes" then data["nodes"].to_h { |n| [ n["id"], label.call(n["id"]) ] }
          when "edges" then edges_of(data, 0).to_h { |e| [ edge_key(e), "#{label.call(e['from'])} verso #{label.call(e['to'])}" ] }
          else {}
          end
        end

        def edge_key(e) = "#{e['from']}>#{e['to']}:#{e['kind']}"

        def effective(data, state)
          eff = Diagrams.effective_states(data)
          eff.empty? ? data : eff.fetch([ state, eff.size - 1 ].min)
        end

        def edges_of(data, state) = Array(effective(data, state)["edges"])

        # ---- what a state prints ------------------------------------------------------------------------

        def plain(text) = text.to_s.gsub(/\\role\{[a-z-]+\}\{([^{}]*)\}/, '\1').delete("$")

        def short(label) = plain(label).split(",").first.to_s.strip

        def edge_text(e) = e["label_it"] || kinds.dig(e["kind"], "label_it") || e["kind"]

        def list_it(items) = items.size <= 1 ? items.join : "#{items[0..-2].join(', ')} e #{items.last}"

        def move_list(nodes, edges)
          name = nodes.to_h { |n| [ n["id"], short(n["label_it"]) ] }
          edges.each_with_index.map do |e, i|
            to = name[e[:to]] || e[:to]
            base = "Da #{name[e[:from]] || e[:from]} #{to.match?(/\Aa/i) ? 'ad' : 'a'} #{to}"
            { "n" => i + 1, "text_it" => e[:label_it] ? "#{base}: #{e[:label_it]}" : base }
          end
        end

        def badge_of(eff, node) = Array(eff["badges"]).find { |b| b["node"] == node["id"] }&.fetch("badge_it") || node["badge_it"]

        def holds_of(eff, node) = Array(Array(eff["holds"]).find { |h| h["node"] == node["id"] }&.fetch("items_it", nil))

        # The description of a state; +kinds+ are the chips the student chose (none: every arrow).
        def describe(data, state: 0, chosen: [])
          eff = effective(data, state)
          hidden = Array(eff["hide"])
          nodes = data["nodes"] + (data["everyone"] ? [ { "id" => EVERYONE, "label_it" => text("everyone") } ] : [])
          nodes = nodes.reject { |n| hidden.include?(n["id"]) }
          parts = [ "Relazioni tra #{list_it(nodes.map { |n| short(n['label_it']) })}." ]
          edges = Array(eff["edges"]).select { |e| (chosen.empty? || chosen.include?(e["kind"])) && !hidden.include?(e["from"]) && !hidden.include?(e["to"]) }
          parts << text("no_edges") if edges.empty?
          move_list(nodes, edges.map { |e| { from: e["from"], to: e["to"], label_it: edge_text(e) } }).each { |m| parts << "#{m['text_it']}." }
          nodes.each do |n|
            badge = badge_of(eff, n)
            parts << "#{short(n['label_it'])}: #{badge}." if badge
            items = holds_of(eff, n)
            parts << "#{short(n['label_it'])} ha: #{list_it(items)}." if items.any?
          end
          parts.join(" ")
        end

        def printed(data, state)
          eff = effective(data, state)
          out = []
          data["nodes"].each { |n| out.push(n["label_it"], n["note_it"], badge_of(eff, n), *holds_of(eff, n)) }
          out << text("everyone") if data["everyone"]
          Array(eff["edges"]).each { |e| out << edge_text(e) }
          out << eff["op_it"]
          out << describe(data, state: state)
          out.compact.map(&:to_s).reject(&:empty?).uniq
        end
      end
    end
  end
end
