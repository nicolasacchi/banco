class SyllabusLine < ApplicationRecord
  ORIGINS = %w[pdf transcript operator].freeze

  belongs_to :syllabus_source

  # Sub-line addresses ("A1"...) for table rows and bulleted lines.
  def parts
    parts_json ? JSON.parse(parts_json) : {}
  end

  # Transcriber lines cannot be cited (E-SOURCE).
  def citable?
    origin != "transcript"
  end
end
