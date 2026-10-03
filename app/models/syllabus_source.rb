class SyllabusSource < ApplicationRecord
  has_many :lines, -> { order(:number) }, class_name: "SyllabusLine"

  # The file's text, rebuilt from the stored physical lines.
  def reconstructed_text
    lines.pluck(:text).map { |line| "#{line}\n" }.join
  end
end
