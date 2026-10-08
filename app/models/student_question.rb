# "Non ho capito": a short line the teacher reads. No model answers the student.
class StudentQuestion < ApplicationRecord
  SECTIONS = %w[why idea example mistakes try solutions book summary practice].freeze

  belongs_to :student
  belongs_to :topic_revision, optional: true
  belongs_to :lesson_revision, optional: true
  belongs_to :practice_serve, optional: true
end
