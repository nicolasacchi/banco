# frozen_string_literal: true

module Lessons
  module Diagrams
    # A flow (A8): one chain from the first node, decisions with 2 or 3 labelled branches, each ending in an end
    # node or rejoining the chain, no cycles.
    module Flow
      module_function

      def state(data, c, _path)
        nodes = data["nodes"]
        ids = nodes.map { |n| n["id"] }
        c.map("/nodes", "node ids must be unique", rule: "ids") if ids.uniq.size != ids.size
        nodes.each_with_index do |n, i|
          c.role("/nodes/#{i}/role", n["role"]) if n["role"]
          words = n["text_it"].gsub(/\$[^$]*\$/, "M").split.size
          max = Validation::Rules.get(:lesson2, :node_words_max) * 2
          c.diagram("/nodes/#{i}/text_it", "a flow node has #{words} words (at most #{max})", rule: "node-words#{i}") if words > max
        end
        out = Hash.new { |h, k| h[k] = [] }
        data["edges"].each_with_index do |e, i|
          from, to = e
          unless ids.include?(from) && ids.include?(to)
            c.map("/edges/#{i}", "the edge names a node that does not exist", rule: "edge-node#{i}")
            next
          end
          if from == to || reaches?(out, to, from)
            c.map("/edges/#{i}", "no cycles: this edge leads back to #{to}", rule: "cycle#{i}")
            next
          end
          out[from] << [ to, i ]
        end
        nodes.each_with_index do |n, i|
          branches = out[n["id"]]
          case n["kind"]
          when "decision"
            c.map("/nodes/#{i}", "a decision has 2 or 3 branches (here #{branches.size})", rule: "branches#{i}") unless (2..3).cover?(branches.size)
            branches.each { |_to, k| c.map("/edges/#{k}", "a branch of a decision says its answer (sì, no, ...)", rule: "branch-label#{k}") if data["edges"][k][2].to_s.empty? }
          when "step"
            c.map("/nodes/#{i}", "a step leads to exactly one next node (here #{branches.size})", rule: "step-out#{i}") unless branches.size == 1
          when "end"
            c.map("/nodes/#{i}", "an end node leads nowhere", rule: "end-out#{i}") unless branches.empty?
          end
        end
        reached = reachable(out, ids.first)
        nodes.each_with_index { |n, i| c.map("/nodes/#{i}", "the node #{n['id']} is not reached from the first node", rule: "unreached#{i}") unless reached.include?(n["id"]) }
      end

      def reaches?(out, from, target, seen = {})
        return true if from == target
        return false if seen[from]

        seen[from] = true
        out[from].any? { |to, _| reaches?(out, to, target, seen) }
      end

      def reachable(out, start)
        seen = {}
        stack = [ start ]
        until stack.empty?
          id = stack.pop
          next if seen[id]

          seen[id] = true
          out[id].each { |to, _| stack << to }
        end
        seen.keys
      end
    end
  end
end
