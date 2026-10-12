# frozen_string_literal: true

module Lessons
  module Diagrams
    # A flow (A8): one chain from the first node, decisions with 2 or 3 labelled branches, each ending in an end
    # node or rejoining the chain, no cycles. `layout: line` (WAVE2 2.1, T4b) is a journey: the stations of the main lane in the order
    # they are written (the edges are that order, none is written), one second lane, at most three returns drawn as arcs, and a token
    # that moves from state to state along the drawn edges or the returns. The browser twin is lesson/diagrams/graph/flow_line.js.
    module Flow
      module_function

      def static(data, c)
        check_line(data, c) if data["layout"] == "line"
      end

      def state(data, c, _path)
        return if data["layout"] == "line"

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

      # What the browser is told: the whitelist projection; for a select check (line only) the stations alone, with no word on them (L3).
      def served(data, mode: :student)
        return StudentBody.diagram(data) unless mode == :select

        stations = data["nodes"].map { |n| { "id" => n["id"], "kind" => "step", "text_it" => "·" } }
        { "type" => "flow", "alt_it" => "Un percorso con #{stations.size} tappe, una dopo l'altra.", "layout" => "line", "nodes" => stations }
      end

      # The select set `stations`: the stations of the main lane in order, then those of the second lane.
      def targets(data, set)
        raise ArgumentError, "flow has no select set #{set.inspect}" unless set.to_s == "stations" && data["layout"] == "line"

        data["nodes"].map { |n| n["id"] } + Array(data.dig("branch", "nodes")).map { |n| n["id"] }
      end

      def printed(data, state)
        return line_printed(data, state) if data["layout"] == "line"

        (data["nodes"].flat_map { |n| [ n["text_it"], n["actor_it"] ] } + data["edges"].map { |e| e[2] }).compact.map(&:to_s).reject(&:empty?).uniq
      end

      # ---- the line layout -------------------------------------------------------------------------------

      def line_caps = Validation::Rules.get(:lesson2, :types, :flow_line)

      def line_text(key) = I18n.t("lesson_graph.scene.#{key}")

      # The edges of a line, as [from, to] id pairs: the main lane in order, the second lane from its start to its end.
      def line_edges(data)
        main = data["nodes"].map { |n| n["id"] }
        pairs = main.each_cons(2).to_a
        branch = data["branch"]
        if branch
          chain = [ branch["from"], *branch["nodes"].map { |n| n["id"] }, branch["to"] ]
          pairs += chain.each_cons(2).to_a
        end
        pairs
      end

      # Position of an id along its lane: [lane, index] (lane 0 is the main one).
      def line_lanes(data)
        lanes = {}
        data["nodes"].each_with_index { |n, i| lanes[n["id"]] = [ 0, i ] }
        Array(data.dig("branch", "nodes")).each_with_index { |n, i| lanes[n["id"]] = [ 1, i ] }
        lanes
      end

      def check_line(data, c)
        caps = line_caps
        main = data["nodes"]
        branch = data["branch"]
        c.diagram("/edges", "a line has no edges: the order of the stations is the order they are written", rule: "line-edges") if data.key?("edges")
        c.diagram("/walk", "walk is for the tree layout only", rule: "line-walk") if data["walk"] || data["case_it"]
        extra = Array(branch && branch["nodes"])
        ids = main.map { |n| n["id"] } + extra.map { |n| n["id"] }
        c.map("/nodes", "node ids must be unique", rule: "ids") if ids.uniq.size != ids.size
        c.diagram("/nodes", "a line has at most #{caps['stations']} stations (here #{main.size})", rule: "stations") if main.size > caps["stations"]
        { "/nodes" => main, "/branch/nodes" => extra }.each do |base, list|
          list.each_with_index do |n, i|
            at = "#{base}/#{i}"
            c.diagram("#{at}/kind", "a station is a step or an end", rule: "station-kind#{at}") if n["kind"] == "decision"
            words = Diagrams.label_words(n["text_it"])
            c.diagram("#{at}/text_it", "a station label has #{words} words (at most #{caps['station_words'].last})", rule: "station-words#{at}") if words > caps["station_words"].last
            c.role("#{at}/role", n["role"]) if n["role"]
            c.add("E-LESSON-ICON", "#{at}/icon", "#{n['icon']} is not an icon of #{c.subject} (config/banco/icons.yml)", rule: "icon#{at}") if n["icon"] && !Lessons::Icons.allowed?(c.subject, n["icon"])
            c.diagram("#{at}/actor_it", "an actor has #{Diagrams.label_words(n['actor_it'])} words (at most 8)", rule: "actor#{at}") if n["actor_it"] && Diagrams.label_words(n["actor_it"]) > 8
          end
        end
        lanes = line_lanes(data)
        if branch
          from = lanes[branch["from"]]
          to = lanes[branch["to"]]
          if from.nil? || to.nil? || from[0] != 0 || to[0] != 0
            c.map("/branch", "the second lane leaves and joins stations of the main lane", rule: "branch-ends")
          elsif from[1] >= to[1]
            c.map("/branch", "the second lane runs forward: it leaves a station before the one it joins", rule: "branch-order")
          end
          c.label("/branch/label_it", branch["label_it"])
        end
        returns = Array(data["returns"])
        c.diagram("/returns", "a line has at most #{caps['returns']} returns (here #{returns.size})", rule: "returns") if returns.size > caps["returns"]
        returns.each_with_index do |r, i|
          at = "/returns/#{i}"
          a = lanes[r["from"]]
          b = lanes[r["to"]]
          if a.nil? || b.nil?
            c.map(at, "a return names a station that does not exist", rule: "return-node#{i}")
          elsif a[0] != b[0] || a[1] <= b[1]
            c.map(at, "a return goes backwards along its own lane", rule: "return-order#{i}")
          end
          c.label("#{at}/label_it", r["label_it"])
        end
        check_line_token(data, c, lanes, returns)
      end

      # The token and its moves: every station exists, and a state's `via` starts where the token was, ends where it is now and
      # follows drawn edges or returns.
      def check_line_token(data, c, lanes, returns)
        c.map("/token", "the token is not a station", rule: "token") if data["token"] && !lanes.key?(data["token"])
        drawn = line_edges(data) + returns.map { |r| [ r["from"], r["to"] ] }
        previous = data["token"]
        Array(data["states"]).each_with_index do |s, i|
          at = "/states/#{i}"
          token = s["token"] || previous
          if s["token"] && !lanes.key?(s["token"])
            c.map("#{at}/token", "the token is not a station", rule: "token#{i}")
            next
          end
          via = s["via"]
          if via
            unknown = via.index { |id| !lanes.key?(id) }
            if unknown
              c.map("#{at}/via/#{unknown}", "via names a station that does not exist", rule: "via-node#{i}")
            elsif previous && via.first != previous
              c.map("#{at}/via", "via starts where the token was (#{previous})", rule: "via-start#{i}")
            elsif token && via.last != token
              c.map("#{at}/via", "via ends where the token is now (#{token})", rule: "via-end#{i}")
            elsif (bad = via.each_cons(2).to_a.index { |pair| !drawn.include?(pair) })
              c.map("#{at}/via", "via goes from #{via[bad]} to #{via[bad + 1]}, which no drawn edge or return joins", rule: "via-edge#{i}")
            end
          end
          previous = token
        end
      end

      # ---- what a line prints --------------------------------------------------------------------------

      def plain(t) = t.to_s.delete("$")

      def cap(t) = "#{t[0]&.upcase}#{t[1..]}"

      def line_describe(data, state: 0)
        eff = Diagrams.effective_states(data)
        now = eff.empty? ? data : eff.fetch([ state, eff.size - 1 ].min)
        names = ->(list) { list.map { |n| plain(n["text_it"]) } }
        list_it = ->(items) { items.size <= 1 ? items.join : "#{items[0..-2].join(', ')} e #{items.last}" }
        by_id = (data["nodes"] + Array(data.dig("branch", "nodes"))).to_h { |n| [ n["id"], n ] }
        parts = [ "Un percorso con #{data['nodes'].size} tappe: #{list_it.call(names.call(data['nodes']))}." ]
        if (b = data["branch"])
          from = plain(by_id[b["from"]]["text_it"])
          to = plain(by_id[b["to"]]["text_it"])
          parts << "Da #{from} parte una strada più corta#{b['label_it'] ? " (#{b['label_it']})" : ''}: #{list_it.call(names.call(b['nodes']))}, e arriva a #{to}."
        end
        Array(data["returns"]).each do |r|
          parts << "Da #{plain(by_id[r['from']]['text_it'])} si torna a #{plain(by_id[r['to']]['text_it'])}#{r['label_it'] ? ": #{r['label_it']}" : ''}."
        end
        if (here = by_id[now["token"]])
          parts << "#{line_text('path_here')} #{plain(here['text_it'])}.#{here['actor_it'] ? " #{cap(plain(here['actor_it']))}." : ''}"
        end
        parts.join(" ")
      end

      def line_printed(data, state)
        out = (data["nodes"] + Array(data.dig("branch", "nodes"))).flat_map { |n| [ n["text_it"], n["actor_it"] ] }
        out << data.dig("branch", "label_it")
        Array(data["returns"]).each { |r| out << r["label_it"] }
        out << (Diagrams.effective_states(data)[state] || {})["op_it"]
        out.push(line_text("return_label"), line_text("station_here")) if data["returns"].to_a.any?
        out << line_describe(data, state: state)
        out.compact.map(&:to_s).reject(&:empty?).uniq
      end
    end
  end
end
