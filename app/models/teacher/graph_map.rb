require "digest"

module Teacher
  # The skill graph as a map (D-221): positioned boxes and curved edges, computed in plain Ruby
  # from the skills of a GraphReview. Pure and deterministic: the same input gives the same
  # coordinates, so the result is cached by the graph revision and a digest of the input.
  #
  # Columns: the longest path from the roots, so every prerequisite edge goes left to right.
  # (The schema's `layer` is a category, core / sec / opt, not a depth; it is shown in the panel.)
  # Edges that span columns pass through invisible waypoints, one per column crossed, which take
  # part in the ordering, so a long edge goes around the boxes and not through them. Inside a
  # column the order comes from a fixed number of barycenter sweeps; ties break by key.
  # A cycle or an unknown prerequisite is never a crash: the edge is left out of the ranking,
  # drawn as a dashed warning line and reported in `warnings`.
  # Deferred cross-subject prerequisites are small stub nodes in the left-most lane. The second
  # year's programme lines (role needed_by) form an extra right-most column that the page shows
  # on request.
  class GraphMap
    NODE_W = 180
    LINE_H = 17
    PAD_Y = 10
    COL_GAP = 64
    ROW_GAP = 16
    MARGIN = 24
    TOP = 36
    WAYPOINT_H = 6
    MAX_LINES = 3
    CHARS = 21
    SWEEPS = 4
    STUB_W = 150
    SEC_W = 220
    SEC_CHARS = 27
    SEC_GROUP_H = 26
    CACHE_SIZE = 32

    Node = Data.define(:key, :kind, :col, :x, :y, :w, :h, :lines)
    Edge = Data.define(:from, :to, :kind, :d)
    Group = Data.define(:label, :x, :y)
    Result = Data.define(:nodes, :edges, :groups, :width, :main_width, :height, :main_height, :warnings, :lane) do
      def node(key) = nodes.find { |n| n.key == key }
    end

    # skills: objects with key, label_it, prerequisites, composite_of, deferred.
    # stub_labels: {foreign skill key => its Italian name}.
    # seconda: [{ id:, source:, line:, text:, section:, skills: [keys] }].
    def self.call(skills:, stub_labels: {}, seconda: [], revision_id: nil)
      input = {
        skills: skills.map { |s| [ s.key, s.label_it, Array(s.prerequisites), Array(s.composite_of), Array(s.deferred).select { |d| d[:where] == :prerequisite }.map { |d| d[:skill] } ] },
        stubs: stub_labels.sort.to_a, seconda: seconda.map { |l| l.slice(:id, :source, :line, :text, :section, :skills) }
      }
      key = [ revision_id, Digest::SHA256.hexdigest(Marshal.dump(input)) ]
      cache_fetch(key) { new(input).result }
    end

    def self.cache_fetch(key)
      @cache_lock ||= Mutex.new
      @cache ||= {}
      @cache_lock.synchronize { return @cache[key] if @cache.key?(key) }
      value = yield
      @cache_lock.synchronize do
        @cache.shift while @cache.size >= CACHE_SIZE
        @cache[key] = value
      end
      value
    end

    def self.reset_cache! = (@cache = {})

    # Labels broken at spaces into at most `max` lines of at most `width` characters; the last one ends in an ellipsis when cut.
    def self.wrap(text, width: CHARS, max: MAX_LINES)
      lines = []
      current = +""
      text.to_s.split.each do |word|
        word = word.dup
        while word.length > width
          lines << current unless current.empty?
          lines << word.slice!(0, width - 1) + "-"
          current = +""
        end
        if current.empty? then current = word
        elsif current.length + 1 + word.length <= width then current << " " << word
        else
          lines << current
          current = word
        end
      end
      lines << current unless current.empty?
      lines << "" if lines.empty?
      return lines if lines.size <= max

      cut = lines.first(max)
      last = cut.last
      cut[-1] = (last.length >= width ? last[0, width - 1] : last) + "…"
      cut
    end

    def initialize(input)
      @skills = input[:skills]
      @stubs = input[:stubs]
      @seconda = input[:seconda]
      @warnings = []
    end

    def result
      build_graph
      rank_columns
      place_waypoints
      order_columns
      assign_coordinates
      shape = nodes_and_edges
      Result.new(**shape, warnings: @warnings.freeze, lane: @lane)
    end

    private

    Item = Struct.new(:id, :kind, :col, :h, :w, :y, :x, :lines)

    # ---- graph

    def build_graph
      @keys = @skills.map(&:first)
      known = @keys.to_set
      @edges = [] # [from, to, kind]
      @skills.each do |key, _label, prerequisites, composite, deferred|
        prerequisites.uniq.each { |p| add_edge(p, key, :prerequisite, known) }
        (composite.uniq - prerequisites).each { |p| add_edge(p, key, :composite, known) }
        deferred.uniq.each { |d| @edges << [ "stub:#{d}", key, :stub ] }
      end
      @stub_keys = @edges.select { |e| e[2] == :stub }.map { |e| e[0].delete_prefix("stub:") }.uniq.sort
      @lane = @stub_keys.any?
    end

    def add_edge(from, to, kind, known)
      if from == to
        @warnings << { kind: :self_loop, keys: [ to ] }
      elsif !known.include?(from)
        @warnings << { kind: :unknown_prerequisite, keys: [ to, from ] }
      else
        @edges << [ from, to, kind ]
      end
    end

    # Longest path from the roots over the edges that remain once the ones closing a cycle are set aside.
    def rank_columns
      succ = Hash.new { |h, k| h[k] = [] }
      @edges.each { |e| succ[e[0]] << e[1] unless e[2] == :stub }
      color = {}
      @back = Set.new
      visit = lambda do |node|
        color[node] = :grey
        succ[node].sort.each do |nxt|
          case color[nxt]
          when :grey then @back << [ node, nxt ]
          when nil then visit.call(nxt)
          end
        end
        color[node] = :black
      end
      @keys.sort.each { |k| visit.call(k) unless color[k] }
      @back.sort.each { |from, to| @warnings << { kind: :cycle, keys: [ from, to ] } }

      preds = Hash.new { |h, k| h[k] = [] }
      @edges.each { |e| preds[e[1]] << e[0] if e[2] != :stub && !@back.include?([ e[0], e[1] ]) }
      @rank = {}
      ranker = lambda do |k|
        @rank[k] ||= preds[k].empty? ? 0 : preds[k].map { |p| ranker.call(p) }.max + 1
      end
      @keys.each { |k| ranker.call(k) }
      @offset = @lane ? 1 : 0
      @col = @keys.to_h { |k| [ k, @rank[k] + @offset ] }
      @col_count = (@col.values.max || -1) + 1
      @col_count = [ @col_count, 1 ].max if @lane
    end

    # ---- items (boxes and invisible waypoints) per column

    def place_waypoints
      @items = {}
      @skills.each do |key, label, *|
        lines = self.class.wrap(label)
        @items[key] = Item.new(key, :skill, @col[key], PAD_Y * 2 + LINE_H * lines.size, NODE_W, nil, nil, lines)
      end
      @stub_keys.each do |k|
        lines = self.class.wrap(@stubs.to_h[k] || k, width: 17, max: 2)
        @items["stub:#{k}"] = Item.new("stub:#{k}", :stub, 0, PAD_Y * 2 + LINE_H * lines.size, STUB_W, nil, nil, lines)
      end
      @chains = [] # [from, to, kind, [item ids from source to target]]
      @links = []  # [left id, right id] between adjacent columns
      @edges.each do |from, to, kind|
        a = @items[from]
        b = @items[to]
        if @back&.include?([ from, to ]) || b.col <= a.col
          @chains << [ from, to, kind, [ from, to ], true ]
          next
        end
        ids = [ from ]
        (a.col + 1...b.col).each do |c|
          id = "wp:#{from}>#{to}@#{c}"
          @items[id] = Item.new(id, :waypoint, c, WAYPOINT_H, NODE_W, nil, nil, [])
          ids << id
        end
        ids << to
        ids.each_cons(2) { |l, r| @links << [ l, r ] }
        @chains << [ from, to, kind, ids, false ]
      end
      @links.uniq!
    end

    def columns_of_items
      Array.new(@col_count) { |c| @items.values.select { |i| i.col == c } }
    end

    # ---- order inside columns: barycenter sweeps

    def order_columns
      @cols = columns_of_items.map { |col| col.sort_by(&:id).map(&:id) }
      left = Hash.new { |h, k| h[k] = [] }
      right = Hash.new { |h, k| h[k] = [] }
      @links.each { |l, r| right[l] << r; left[r] << l }
      @left = left
      @right = right
      SWEEPS.times do
        (1...@col_count).each { |c| reorder(c, left) }
        (@col_count - 2).downto(0) { |c| reorder(c, right) }
      end
    end

    def reorder(c, neighbours)
      position = {}
      @cols.each { |col| col.each_with_index { |id, i| position[id] = i } }
      current = position
      keyed = @cols[c].map do |id|
        ns = neighbours[id]
        bary = ns.empty? ? current[id].to_f : ns.sum { |n| current[n] } / ns.size.to_f
        [ bary, current[id], id ]
      end
      @cols[c] = keyed.sort_by { |b, i, id| [ b.round(6), id.start_with?("wp:") ? 0 : 1, i, id ] }.map(&:last)
    end

    # ---- coordinates

    def assign_coordinates
      widths = Array.new(@col_count) { |c| c.zero? && @lane ? STUB_W : NODE_W }
      xs = []
      cursor = MARGIN
      widths.each { |w| xs << cursor; cursor += w + COL_GAP }
      @main_width = cursor - COL_GAP + MARGIN
      @xs = xs
      @cols.each_with_index do |ids, c|
        ids.each { |id| @items[id].x = xs[c] }
        stack(ids)
      end
      4.times do
        (1...@col_count).each { |c| settle(c, @left) }
        (@col_count - 2).downto(0) { |c| settle(c, @right) }
      end
      min = @items.values.map(&:y).min || 0
      @items.each_value { |i| i.y = (i.y - min + TOP).round(1) }
      @height = ((@items.values.map { |i| i.y + i.h }.max || TOP) + MARGIN).round(1)
    end

    def stack(ids)
      y = 0.0
      ids.each do |id|
        @items[id].y = y
        y += @items[id].h + ROW_GAP
      end
    end

    # Pull a column toward the centres of its neighbours without letting boxes touch.
    def settle(c, neighbours)
      ids = @cols[c]
      wanted = ids.map do |id|
        ns = neighbours[id]
        ns.empty? ? center(id) : ns.sum { |n| center(n) } / ns.size
      end
      tops = []
      bottom = -Float::INFINITY
      ids.each_with_index do |id, i|
        top = [ wanted[i] - @items[id].h / 2.0, bottom + ROW_GAP ].max
        tops << top
        bottom = top + @items[id].h
      end
      shift = ids.each_index.sum { |i| wanted[i] - (tops[i] + @items[ids[i]].h / 2.0) } / ids.size
      ids.each_with_index { |id, i| @items[id].y = tops[i] + shift }
    end

    def center(id) = @items[id].y + @items[id].h / 2.0

    # ---- result

    def nodes_and_edges
      nodes = @items.values.reject { |i| i.kind == :waypoint }.sort_by { |i| [ i.col, i.y, i.id ] }.map do |i|
        key = i.kind == :stub ? i.id.delete_prefix("stub:") : i.id
        Node.new(key, i.kind, i.col, i.x, i.y, i.w, i.h.to_f, i.lines)
      end
      edges = @chains.map do |from, to, kind, ids, odd|
        Edge.new(from.delete_prefix("stub:"), to, odd ? :warning : kind, path(ids, odd))
      end
      groups = []
      width = @main_width
      main_height = @height
      if @seconda.any?
        sec_nodes, sec_edges, groups, width = seconda_column(nodes.select { |n| n.kind == :skill })
        nodes += sec_nodes
        edges += sec_edges
        @height = [ @height, sec_nodes.map { |n| n.y + n.h }.max.to_f + MARGIN ].max.round(1)
      end
      if @lane
        groups << Group.new("lane", @xs[0], TOP - 14)
      end
      { nodes: nodes, edges: edges, groups: groups, width: width, main_width: @main_width, height: @height, main_height: main_height }
    end

    def path(ids, odd)
      pts = []
      first = @items[ids.first]
      last = @items[ids.last]
      pts << [ first.x + first.w, center(first.id) ]
      ids[1...-1].each do |id|
        i = @items[id]
        pts << [ i.x, center(id) ] << [ i.x + i.w, center(id) ]
      end
      pts << [ last.x, center(last.id) ]
      d = +"M#{fmt(pts[0][0])} #{fmt(pts[0][1])}"
      if odd
        mid = [ (pts[0][0] + pts[-1][0]) / 2.0, [ pts[0][1], pts[-1][1] ].max + 40 ]
        return d << " C#{fmt(pts[0][0] + 60)} #{fmt(mid[1])} #{fmt(pts[-1][0] - 60)} #{fmt(mid[1])} #{fmt(pts[-1][0])} #{fmt(pts[-1][1])}"
      end
      pts.each_cons(2).each_with_index do |(p, q), n|
        # Inside a column (the waypoint's own width) the line runs straight.
        d << if n.odd? then " L#{fmt(q[0])} #{fmt(q[1])}"
        else
          dx = (q[0] - p[0]) * 0.5
          " C#{fmt(p[0] + dx)} #{fmt(p[1])} #{fmt(q[0] - dx)} #{fmt(q[1])} #{fmt(q[0])} #{fmt(q[1])}"
        end
      end
      d
    end

    def fmt(n) = format("%.1f", n)

    # The second year's lines: one box per cited line, grouped by section, each with a thin edge
    # from every skill that cites it as needed_by.
    def seconda_column(skill_nodes)
      by_key = skill_nodes.to_h { |n| [ n.key, n ] }
      x = @main_width - MARGIN + COL_GAP
      lines = @seconda.map do |l|
        ys = Array(l[:skills]).filter_map { |k| by_key[k] }.map { |n| n.y + n.h / 2.0 }
        { line: l, wanted: ys.empty? ? 0.0 : ys.sum / ys.size, section: l[:section].to_s }
      end
      section_pos = lines.group_by { |l| l[:section] }.transform_values { |ls| ls.sum { |l| l[:wanted] } / ls.size }
      lines.sort_by! { |l| [ section_pos[l[:section]].round(3), l[:section], l[:wanted].round(3), l[:line][:source].to_s, l[:line][:line].to_i ] }
      nodes = []
      groups = []
      y = TOP.to_f
      previous = nil
      lines.each do |l|
        if l[:section] != previous
          y = [ y, l[:wanted] - SEC_GROUP_H - 20 ].max if previous.nil?
          groups << Group.new(l[:section].empty? ? "none" : l[:section], x, y)
          y += SEC_GROUP_H
          previous = l[:section]
        end
        label = [ "#{l[:line][:source]} · #{l[:line][:line]}" ] + self.class.wrap(l[:line][:text], width: SEC_CHARS, max: 2)
        h = (PAD_Y * 2 + LINE_H * label.size).to_f
        nodes << Node.new(l[:line][:id], :seconda, @col_count, x, y.round(1), SEC_W, h, label)
        y += h + ROW_GAP
      end
      edges = lines.flat_map do |l|
        target = nodes.find { |n| n.key == l[:line][:id] }
        Array(l[:line][:skills]).filter_map { |k| by_key[k] }.map do |s|
          sx = s.x + s.w
          sy = s.y + s.h / 2.0
          ty = target.y + target.h / 2.0
          dx = (target.x - sx) * 0.5
          Edge.new(s.key, target.key, :seconda, "M#{fmt(sx)} #{fmt(sy)} C#{fmt(sx + dx)} #{fmt(sy)} #{fmt(target.x - dx)} #{fmt(ty)} #{fmt(target.x)} #{fmt(ty)}")
        end
      end
      [ nodes, edges, groups, x + SEC_W + MARGIN ]
    end
  end
end
