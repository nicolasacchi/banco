module Syllabus
  # A programme holds one "## <subject>" section per subject (lines starting with
  # "## ", not "###"). This gives each line the heading of the section it sits in, so
  # that a citation of another subject's line can be told from the graph's own.
  module Sections
    HEADING = /\A##\s+(\S.*?)\s*\z/

    module_function

    # rows: objects with number and text, in line order.
    # Returns { number => "heading" } for the lines under a "## " heading (the heading
    # line included); lines before the first heading are not in it.
    def call(rows)
      out = {}
      current = nil
      rows.each do |row|
        current = Regexp.last_match(1) if row.text.to_s.strip =~ HEADING
        out[row.number] = current if current
      end
      out
    end
  end
end
