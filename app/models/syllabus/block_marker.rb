module Syllabus
  # The programme puts its star marker (★ studied integration, ☆ in progress) on the
  # header line of a block only; the lines under it carry none. This derives the
  # marker such a line inherits, so that an agent that reads one line (or the
  # validator that checks a citation) still sees it.
  #
  # A marked line that looks like a header (ends with ":" or is short and has no
  # closing punctuation) opens a block. The block runs over the following lines until
  # the next marked line, a blank, a transcriber line or a line ending with ":"
  # (D-138: a short bullet inside the block no longer closes it, unless the line
  # before it ended a sentence: then it is a new heading, D-142). A line outside any
  # block that looks like a header opens nothing. A marked line that is plain content
  # opens nothing.
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
      closed_prose = false # the last line of the open block ended a sentence (D-142)
      rows.each do |row|
        text = row.text.to_s.strip
        if row.origin == "transcript" || text.empty?
          open = nil
        elsif row.marker
          open = header?(row.text) ? { marker: row.marker, from: row.number } : nil
          closed_prose = false
        elsif open && closed_prose && header?(row.text)
          # A short unpunctuated line after a finished sentence is a new heading (D-142).
          open = nil
          closed_prose = false
        elsif open && !text.end_with?(":")
          closed_prose = text.match?(/[.;!?]\z/)
          # Inside a block a short line is a bullet, not a header (D-138).
          out[row.number] = open
        elsif header?(row.text)
          open = nil
        elsif open
          out[row.number] = open
          closed_prose = false
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
