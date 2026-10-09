# frozen_string_literal: true

module Lessons
  module Diagrams
    # An area model: rows x cols labels, cells filled by the author or by a later state.
    module AreaModel
      module_function

      def static(data, c)
        data["rows"].to_a.each_with_index { |l, i| c.label("/rows/#{i}", l) }
        data["cols"].to_a.each_with_index { |l, i| c.label("/cols/#{i}", l) }
      end

      def state(eff, c, path)
        cells = eff["cells"] or return
        rows = eff["rows"].to_a.size
        cols = eff["cols"].to_a.size
        c.diagram("#{path}/cells", "cells are rows x cols: #{rows} rows of #{cols} cells", rule: "cells#{path}") unless cells.size == rows && cells.all? { |r| r.is_a?(Array) && r.size == cols }
        cells.flatten.each_with_index { |l, i| c.label("#{path}/cells/#{i / [ cols, 1 ].max}/#{i % [ cols, 1 ].max}", l) }
      end
    end
  end
end
