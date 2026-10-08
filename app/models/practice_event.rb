class PracticeEvent < ApplicationRecord
  KINDS = %w[lesson_opened lesson_solution_shown hint_shown solution_shown].freeze

  belongs_to :student
  belongs_to :practice_serve, optional: true
  belongs_to :topic_revision, optional: true
  belongs_to :lesson_revision, optional: true
end
