class PracticeAttempt < ApplicationRecord
  SOURCES = %w[text mathlive button].freeze

  belongs_to :student
  belongs_to :practice_serve
  has_many :gradings, class_name: "PracticeGrading"

  def latest_grading = gradings.max_by(&:seq)
end
