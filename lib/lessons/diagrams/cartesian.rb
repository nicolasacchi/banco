# frozen_string_literal: true

module Lessons
  module Diagrams
    # The Cartesian plane: a window, lines in y = mx + q, x = k or ax + by = c with rational coefficients,
    # points that lie exactly on the lines they name, segments.
    module Cartesian
      TERM = /\A([+-]?)((?:0|[1-9][0-9]*)(?:,[0-9]+)?(?:\/[1-9][0-9]*)?)?([xy])?\z/

      module_function

      # {a:, b:, c:} for a x + b y = c, or nil when +text+ is not one of the three forms.
      def line(text)
        left, right, extra = text.to_s.delete(" ").split("=", 3)
        return nil if left.nil? || right.nil? || extra || left.empty? || right.empty?

        r = side(right) or return nil
        if left == "x"
          { a: 1r, b: 0r, c: r[:c] } if r[:x].zero? && r[:y].zero?
        elsif left == "y"
          { a: -r[:x], b: 1r, c: r[:c] } if r[:y].zero?
        elsif (l = side(left)) && l[:c].zero? && (!l[:x].zero? || !l[:y].zero?) && r[:x].zero? && r[:y].zero?
          { a: l[:x], b: l[:y], c: r[:c] }
        end
      end

      # A sum of terms: {x:, y:, c:} Rationals; nil for anything that is not a linear sum of rational terms.
      def side(text)
        sums = { x: 0r, y: 0r, c: 0r }
        pieces = text.scan(/[+-]?[^+-]+/)
        return nil unless pieces.join == text

        pieces.each do |piece|
          m = piece.match(TERM) or return nil
          return nil if m[2].nil? && m[3].nil?

          coef = m[2] ? Lessons::Num.parse(m[2]) : 1r
          return nil if coef.nil?

          coef = -coef if m[1] == "-"
          sums[(m[3] || "c").to_sym] += coef
        end
        sums
      end

      def static(data, c)
        %w[x y].each do |axis|
          lo = Diagrams.num(data[axis][0])
          hi = Diagrams.num(data[axis][1])
          c.diagram("/#{axis}", "the window of #{axis} goes from a smaller to a larger number", rule: "window-#{axis}") if lo && hi && lo >= hi
        end
        ids = {}
        data["lines"].to_a.each_with_index do |l, i|
          if ids.key?(l["id"])
            c.diagram("/lines/#{i}/id", "the line id #{l['id']} is used twice", rule: "line-id-#{i}")
          end
          ids[l["id"]] = line(l["eq"])
          c.diagram("/lines/#{i}/eq", "eq is y = mx + q, x = k or ax + by = c with exact numbers (here #{l['eq'].inspect})", rule: "eq-#{i}") if ids[l["id"]].nil?
          c.role("/lines/#{i}/role", l["role"]) if l["role"]
          c.label("/lines/#{i}/label_it", l["label_it"])
        end
      end

      def state(eff, c, path)
        xs = eff["x"].map { |v| Diagrams.num(v) }
        ys = eff["y"].map { |v| Diagrams.num(v) }
        return if xs.any?(&:nil?) || ys.any?(&:nil?) || xs[0] >= xs[1] || ys[0] >= ys[1]

        lines = eff["lines"].to_a.to_h { |l| [ l["id"], line(l["eq"]) ] }
        inside = ->(x, y) { x && y && x >= xs[0] && x <= xs[1] && y >= ys[0] && y <= ys[1] }
        eff["points"].to_a.each_with_index do |p, i|
          at = "#{path}/points/#{i}"
          px = Diagrams.num(p["x"])
          py = Diagrams.num(p["y"])
          c.diagram(at, "the point (#{p['x']}, #{p['y']}) is outside the window", rule: "point#{at}") unless inside.call(px, py)
          c.role("#{at}/role", p["role"]) if p["role"]
          c.label("#{at}/label_it", p["label_it"])
          p["on_lines"].to_a.each do |id|
            ln = lines[id]
            if !lines.key?(id)
              c.diagram("#{at}/on_lines", "the point names a line #{id} that does not exist", rule: "on-unknown#{at}")
            elsif ln && px && py && ln[:a] * px + ln[:b] * py != ln[:c]
              c.diagram("#{at}/on_lines", "the point (#{p['x']}, #{p['y']}) does not lie on the line #{id}", rule: "on-line#{at}")
            end
          end
        end
        eff["segments"].to_a.each_with_index do |s, i|
          at = "#{path}/segments/#{i}"
          a = s["from"].map { |v| Diagrams.num(v) }
          b = s["to"].map { |v| Diagrams.num(v) }
          c.diagram(at, "a segment has both ends inside the window", rule: "segment#{at}") unless inside.call(*a) && inside.call(*b)
          c.role("#{at}/role", s["role"]) if s["role"]
        end
      end
    end
  end
end
