# frozen_string_literal: true

module Maps
  # Plane geometry for the map bases (T5, W2-1): projections, clipping, simplification, paths.
  # Everything here is pure and deterministic; no I/O. Rings are arrays of [lon, lat] (closed
  # rings are stored without the repeated last point).
  module Geom
    module_function

    # Equal Earth (Savric, Patterson, Jenny 2018), the projection of the world and the continents.
    EE_A1 = 1.340264
    EE_A2 = -0.081106
    EE_A3 = 0.000893
    EE_A4 = 0.003796
    EE_M = Math.sqrt(3) / 2

    def rad(deg) = deg * Math::PI / 180

    # [x, y] with y up, in the projection's own unit (about 2.7 wide for the whole Earth).
    def equal_earth(lon, lat)
      l = rad(lon)
      t = Math.asin(EE_M * Math.sin(rad(lat)))
      t2 = t * t
      t6 = t2**3
      x = l * Math.cos(t) / (EE_M * (EE_A1 + 3 * EE_A2 * t2 + t6 * (7 * EE_A3 + 9 * EE_A4 * t2)))
      y = t * (EE_A1 + EE_A2 * t2 + t6 * (EE_A3 + EE_A4 * t2))
      [ x, y ]
    end

    # Lambert azimuthal equal-area, polar aspect: north up for no one, so 0 degrees points down in
    # the north (the usual atlas view) and up in the south.
    def azimuthal(lon, lat, pole)
      l = rad(lon)
      if pole == :north
        r = 2 * Math.sin(rad(90 - lat) / 2)
        [ r * Math.sin(l), -r * Math.cos(l) ]
      else
        r = 2 * Math.sin(rad(90 + lat) / 2)
        [ r * Math.sin(l), r * Math.cos(l) ]
      end
    end

    def raw_project(type, lon, lat)
      case type
      when "equal_earth" then equal_earth(lon, lat)
      when "mercator" then [ rad(lon), Math.log(Math.tan(Math::PI / 4 + rad(lat) / 2)) ]
      when "azimuthal_north" then azimuthal(lon, lat, :north)
      when "azimuthal_south" then azimuthal(lon, lat, :south)
      else raise ArgumentError, "unknown projection #{type}"
      end
    end

    # A fitted projection: a type, a scale and a translation into a viewBox of the given width.
    # screen x = tx + scale * px, screen y = ty - scale * py. `rect` is the viewBox in screen units.
    Projection = Struct.new(:type, :scale, :tx, :ty, :width, :height) do
      def project(lon, lat)
        px, py = Geom.raw_project(type, lon, lat)
        [ tx + scale * px, ty - scale * py ]
      end

      def rect = [ 0.0, 0.0, width, height ]

      def to_h = { "type" => type, "scale" => scale.round(4), "tx" => tx.round(3), "ty" => ty.round(3) }
    end

    # Fits the window [w, s, e, n] into a viewBox of `width` (the height follows). With `crop` the
    # viewBox is the largest upright rectangle inside the window's projected outline (the curved
    # meridians of Equal Earth leave the corners of the bounding box empty); without it, the
    # bounding box (the world, the poles).
    def fit(type, window, width, crop: false)
      w, s, e, n = window
      steps = 90
      left = []
      right = []
      all = []
      (0..steps).each do |i|
        f = i.to_f / steps
        lon = w + (e - w) * f
        lat = s + (n - s) * f
        l = raw_project(type, w, lat)
        r = raw_project(type, e, lat)
        left << l
        right << r
        all.push(raw_project(type, lon, s), raw_project(type, lon, n), l, r)
      end
      xs = all.map(&:first)
      ys = all.map(&:last)
      x0 = xs.min
      x1 = xs.max
      if crop
        x0 = left.map(&:first).max
        x1 = right.map(&:first).min
      end
      scale = width / (x1 - x0)
      Projection.new(type, scale, -x0 * scale, ys.max * scale, width, (ys.max - ys.min) * scale)
    end

    # Adds points so that no edge is longer than `step` degrees.
    def densify(ring, step)
      out = []
      ring.each_with_index do |p, i|
        q = ring[(i + 1) % ring.size]
        out << p
        d = [ (q[0] - p[0]).abs, (q[1] - p[1]).abs ].max
        next unless d > step
        n = (d / step).ceil
        (1...n).each { |k| out << [ p[0] + (q[0] - p[0]) * k / n, p[1] + (q[1] - p[1]) * k / n ] }
      end
      out
    end

    # Sutherland-Hodgman against the window [w, s, e, n]. May leave zero-width bridges along the
    # window's edge for a concave ring; they draw nothing.
    def clip_ring(ring, window)
      w, s, e, n = window
      edges = [
        [ ->(p) { p[0] >= w }, ->(a, b) { t = (w - a[0]) / (b[0] - a[0]); [ w, a[1] + t * (b[1] - a[1]) ] } ],
        [ ->(p) { p[0] <= e }, ->(a, b) { t = (e - a[0]) / (b[0] - a[0]); [ e, a[1] + t * (b[1] - a[1]) ] } ],
        [ ->(p) { p[1] >= s }, ->(a, b) { t = (s - a[1]) / (b[1] - a[1]); [ a[0] + t * (b[0] - a[0]), s ] } ],
        [ ->(p) { p[1] <= n }, ->(a, b) { t = (n - a[1]) / (b[1] - a[1]); [ a[0] + t * (b[0] - a[0]), n ] } ]
      ]
      out = ring
      edges.each do |inside, cut|
        input = out
        out = []
        next if input.empty?
        prev = input.last
        input.each do |cur|
          if inside.call(cur)
            out << cut.call(prev, cur) unless inside.call(prev)
            out << cur
          elsif inside.call(prev)
            out << cut.call(prev, cur)
          end
          prev = cur
        end
      end
      out.size < 3 ? [] : out
    end

    # Liang-Barsky for polylines: the pieces inside the window.
    def clip_line(points, window)
      w, s, e, n = window.map(&:to_f)
      pieces = []
      cur = []
      points.each_cons(2) do |a, b|
        t0 = 0.0
        t1 = 1.0
        dx = (b[0] - a[0]).to_f
        dy = (b[1] - a[1]).to_f
        ok = [ [ -dx, a[0] - w ], [ dx, e - a[0] ], [ -dy, a[1] - s ], [ dy, n - a[1] ] ].all? do |p, q|
          if p.zero?
            q >= 0
          else
            r = q / p
            if p < 0
              next false if r > t1
              t0 = r if r > t0
            else
              next false if r < t0
              t1 = r if r < t1
            end
            true
          end
        end
        if ok
          pa = [ a[0] + t0 * dx, a[1] + t0 * dy ]
          pb = [ a[0] + t1 * dx, a[1] + t1 * dy ]
          cur << pa if cur.empty?
          cur << pb
          if t1 < 1.0
            pieces << cur
            cur = []
          end
        else
          pieces << cur unless cur.empty?
          cur = []
        end
      end
      pieces << cur unless cur.empty?
      pieces.select { |p| p.size >= 2 }
    end

    def signed_area(ring)
      a = 0.0
      ring.each_with_index do |p, i|
        q = ring[(i + 1) % ring.size]
        a += p[0] * q[1] - q[0] * p[1]
      end
      a / 2
    end

    # Douglas-Peucker on a closed ring (anchored at point 0 and the farthest point) or an open line.
    def simplify(points, eps, closed: true)
      return points if points.size <= 3
      eps2 = eps * eps
      keep = Array.new(points.size, false)
      stack = []
      if closed
        far = (1...points.size).max_by { |i| dist2(points[i], points[0]) }
        keep[0] = keep[far] = true
        stack << [ 0, far ] << [ far, points.size ]
      else
        keep[0] = keep[-1] = true
        stack << [ 0, points.size - 1 ]
      end
      until stack.empty?
        i, j = stack.pop
        a = points[i]
        b = points[j % points.size]
        best = -1.0
        idx = nil
        ((i + 1)...j).each do |k|
          d = seg_dist2(points[k], a, b)
          if d > best
            best = d
            idx = k
          end
        end
        next unless idx && best > eps2
        keep[idx] = true
        stack << [ i, idx ] << [ idx, j ]
      end
      points.each_index.select { |i| keep[i] }.map { |i| points[i] }
    end

    def dist2(a, b) = (a[0] - b[0])**2 + (a[1] - b[1])**2

    def seg_dist2(p, a, b)
      dx = (b[0] - a[0]).to_f
      dy = (b[1] - a[1]).to_f
      len2 = dx * dx + dy * dy
      return dist2(p, a) if len2.zero?
      t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / len2
      t = t.clamp(0.0, 1.0)
      dist2(p, [ a[0] + t * dx, a[1] + t * dy ])
    end

    # Joins rings that share edges (a shared edge is walked in opposite directions by its two
    # neighbours) into the rings of their union. Rings must all be oriented alike; see `orient`.
    def dissolve(rings, digits = 4)
      key = ->(p) { [ p[0].round(digits), p[1].round(digits) ] }
      edges = {}
      rings.each do |ring|
        ring.each_with_index do |p, i|
          q = ring[(i + 1) % ring.size]
          a = key.call(p)
          b = key.call(q)
          next if a == b
          if edges.key?([ b, a ])
            edges.delete([ b, a ])
          else
            edges[[ a, b ]] = [ p, q ]
          end
        end
      end
      out_by_start = Hash.new { |h, k| h[k] = [] }
      edges.each_key { |a, b| out_by_start[a] << b }
      result = []
      remaining = edges.dup
      remaining.each_key do |(a, b)|
        next unless edges.key?([ a, b ]) && edges[[ a, b ]]
        ring = []
        cur = [ a, b ]
        loop do
          break unless edges.key?(cur)
          pa, = edges.delete(cur)
          ring << pa
          nxt = out_by_start[cur[1]].find { |c| edges.key?([ cur[1], c ]) }
          break unless nxt
          cur = [ cur[1], nxt ]
        end
        result << ring if ring.size >= 3
      end
      result
    end

    # Exterior rings counter-clockwise, holes clockwise (in lon/lat with y up).
    def orient(ring, exterior)
      ccw = signed_area(ring) > 0
      ccw == exterior ? ring : ring.reverse
    end

    # The centre of the widest horizontal stretch through the ring's centroid: a label anchor that
    # lies inside a concave shape.
    def anchor(ring)
      a = signed_area(ring)
      cx = cy = 0.0
      ring.each_with_index do |p, i|
        q = ring[(i + 1) % ring.size]
        c = p[0] * q[1] - q[0] * p[1]
        cx += (p[0] + q[0]) * c
        cy += (p[1] + q[1]) * c
      end
      return ring.first if a.zero?
      cx /= 6 * a
      cy /= 6 * a
      return [ cx, cy ] if inside?(ring, [ cx, cy ])
      xs = []
      ring.each_with_index do |p, i|
        q = ring[(i + 1) % ring.size]
        next if (p[1] > cy) == (q[1] > cy)
        xs << p[0] + (cy - p[1]) / (q[1] - p[1]) * (q[0] - p[0])
      end
      xs.sort!
      best = xs.each_slice(2).select { |s| s.size == 2 }.max_by { |s, e| e - s }
      best ? [ (best[0] + best[1]) / 2, cy ] : [ cx, cy ]
    end

    def inside?(ring, pt)
      c = false
      ring.each_with_index do |p, i|
        q = ring[(i + 1) % ring.size]
        next unless (p[1] > pt[1]) != (q[1] > pt[1])
        c = !c if pt[0] < (q[0] - p[0]) * (pt[1] - p[1]) / (q[1] - p[1]) + p[0]
      end
      c
    end

    # One decimal, as the shortest text: "12.3", "-4", "0.5".
    def num(v)
      r = (v * 10).round
      return "0" if r.zero?
      s = r.to_s
      s = r.negative? ? "-#{s[1..].rjust(2, '0')}" : s.rjust(2, "0")
      s.insert(-2, ".")
      s.sub(/\.0\z/, "").sub(/\A(-?)0\./, '\1.')
    end

    # SVG path text for rings (closed) or lines (open), absolute start and relative steps. Values
    # are rounded to tenths of a unit and the steps computed between rounded points, so rounding
    # never accumulates.
    def path(shapes, closed: true)
      shapes.filter_map do |pts|
        r = pts.map { |x, y| [ (x * 10).round, (y * 10).round ] }
        r = r.each_with_index.reject { |p, i| i.positive? && p == r[i - 1] }.map(&:first)
        next if r.size < (closed ? 3 : 2)
        d = +"M#{num(r[0][0] / 10.0)} #{num(r[0][1] / 10.0)}l"
        d << r.each_cons(2).map { |a, b| "#{num((b[0] - a[0]) / 10.0)} #{num((b[1] - a[1]) / 10.0)}" }.join(" ")
        d << "z" if closed
        d
      end.join
    end

    # The area of a projected ring, positive.
    def area(ring) = signed_area(ring).abs

    def bbox(rings)
      xs = rings.flatten(1).map(&:first)
      ys = rings.flatten(1).map(&:last)
      [ xs.min, ys.min, xs.max, ys.max ]
    end
  end
end
