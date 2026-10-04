module Syllabus
  # The programme puts its star marker (★ studied integration, ☆ in progress) on the
  # header line of a block only; the lines under it carry none. This derives the
  # marker such a line inherits, so that an agent that reads one line (or the
  # validator that checks a citation) still sees it.
  #
  # A marked line that looks like a header (ends with ":" or is short and has no
  # closing punctuation) opens a block. The block runs over the following content
  # lines until the next marked line, the next header-looking line, a blank or a
  # transcriber line. A marked line that is plain content opens nothing. The rule is
  # a heuristic on purpose: it can end a block early (a short bullet looks like a
  # header), never extend it past a header, so it under-reports rather than invents.
  module BlockMarker
    SHORT = 50
    MARKER = /\A(?:★☆|☆★|★|☆)\s*/

    module_function

    # rows: objects with number, text, origin, marker, in line order.
    # Returns { number => { marker: "★", from: header_number } } for the inherited
    # lines only (lines with their own marker are not in it).
    def call(rows)
      out = {}
      open = nil
      rows.each do |row|
        if row.origin == "transcript" || row.text.to_s.strip.empty?
          open = nil
        elsif row.marker
          open = header?(row.text) ? { marker: row.marker, from: row.number } : nil
        elsif header?(row.text)
          open = nil
        elsif open
          out[row.number] = open
        end
      end
      out
    end

    def header?(text)
      body = text.to_s.sub(MARKER, "").strip
      body.end_with?(":") || (body.length <= SHORT && !body.match?(/[.;!?]\z/))
    end

    # The scope a marker stands for (brief: star = integration_studied, empty star or
    # both = in_progress, no marker = studied).
    def scopes_for(marker)
      case marker
      when "★" then %w[integration_studied]
      when "☆", "★☆", "☆★" then %w[in_progress]
      else %w[studied]
      end
    end
  end
end
