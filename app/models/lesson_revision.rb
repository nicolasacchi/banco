class LessonRevision < ApplicationRecord
  belongs_to :lesson
  belongs_to :base_revision, class_name: "LessonRevision", optional: true
  belongs_to :author_session, class_name: "AgentSession", optional: true
  has_many :reviews, class_name: "LessonReview"

  def body = JSON.parse(body_json)
  def warnings = JSON.parse(warnings_json)
end
