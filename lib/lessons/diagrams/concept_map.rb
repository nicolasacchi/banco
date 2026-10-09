# frozen_string_literal: true

module Lessons
  module Diagrams
    # A concept map (A8): a tree of depth at most 3 with at most 4 children per node, up to 3 dashed cross links.
    module ConceptMap
      MAX_DEPTH = 3
      MAX_CHILDREN = 4

      module_function

      def state(data, c, _path)
        rules = Validation::Rules
        node_max = rules.get(:lesson2, :node_words_max)
        edge_max = rules.get(:lesson2, :edge_words_max)
        ids = data["nodes"].map { |n| n["id"] }
        data["nodes"].each_with_index do |n, i|
          at = "/nodes/#{i}"
          words = n["text_it"].gsub(/\$[^$]*\$/, "M").split.size
          c.diagram("#{at}/text_it", "a node has #{words} words (at most #{node_max})", rule: "node-words#{at}") if words > node_max
          c.role("#{at}/role", n["role"]) if n["role"]
          c.add("E-LESSON-ICON", "#{at}/icon", "#{n['icon']} is not an icon of #{c.subject} (config/banco/icons.yml)", rule: "icon#{at}") if n["icon"] && !Lessons::Icons.allowed?(c.subject, n["icon"])
        end
        c.map("/nodes", "node ids must be unique", rule: "ids") if ids.uniq.size != ids.size
        c.map("/root", "the root #{data['root']} is not a node", rule: "root") unless ids.include?(data["root"])

        parent = {}
        children = Hash.new(0)
        data["edges"].each_with_index do |e, i|
          at = "/edges/#{i}"
          words = e["label_it"].to_s.split.size
          c.diagram("#{at}/label_it", "an edge label has #{words} words (at most #{edge_max})", rule: "edge-words#{at}") if words > edge_max
          unless ids.include?(e["from"]) && ids.include?(e["to"])
            c.map(at, "the edge names a node that does not exist", rule: "edge-node#{at}")
            next
          end
          if e["to"] == data["root"] || parent.key?(e["to"])
            c.map(at, "the edges form a tree: #{e['to']} already has a parent (or is the root)", rule: "tree#{at}")
            next
          end
          parent[e["to"]] = e["from"]
          children[e["from"]] += 1
        end
        c.map("/edges", "at most #{MAX_CHILDREN} children per node", rule: "children") if children.values.any? { |n| n > MAX_CHILDREN }
        return unless ids.include?(data["root"])

        depth = lambda do |id|
          d = 0
          seen = {}
          while (id = parent[id])
            return Float::INFINITY if seen[id]

            seen[id] = true
            d += 1
          end
          d
        end
        ids.each_with_index do |id, i|
          next if id == data["root"]

          d = depth.call(id)
          if d == Float::INFINITY || !parent.key?(id) && d.zero?
            c.map("/nodes/#{i}", "the node #{id} is not reached from the root", rule: "unreached#{i}")
          elsif d > MAX_DEPTH
            c.map("/nodes/#{i}", "the tree has depth #{d} (at most #{MAX_DEPTH})", rule: "depth#{i}")
          end
        end
        data["links"].to_a.each_with_index do |l, i|
          at = "/links/#{i}"
          c.map("#{at}/from", "the link names a node that does not exist", rule: "link-from#{i}") unless ids.include?(l["from"])
          c.map("#{at}/to", "the link names a node that does not exist", rule: "link-to#{i}") unless ids.include?(l["to"])
          words = l["label_it"].to_s.split.size
          c.diagram("#{at}/label_it", "a link label has #{words} words (at most #{edge_max})", rule: "link-words#{i}") if words > edge_max
        end
      end
    end
  end
end
