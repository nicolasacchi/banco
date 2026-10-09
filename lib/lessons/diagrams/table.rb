# frozen_string_literal: true

module Lessons
  module Diagrams
    # A table (the summary card's, A8): every row has as many cells as the header.
    module Table
      module_function

      def state(data, c, _path)
        width = data["header"].size
        data["rows"].each_with_index do |row, i|
          c.add("E-LESSON-BLOCK", "/rows/#{i}", "every row has as many cells as the header (#{width}), here #{row.size}", rule: "ragged#{i}") unless row.size == width
        end
      end
    end
  end
end
