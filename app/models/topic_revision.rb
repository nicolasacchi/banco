# Pins one lesson revision and, per skill, the practice item revisions (ids only). The
# teacher approves topic revisions. The topic is its lesson.
class TopicRevision < ApplicationRecord
  belongs_to :lesson
  belongs_to :course_revision
  belongs_to :lesson_revision
  belongs_to :author_session, class_name: "AgentSession", optional: true

  def body = JSON.parse(body_json)
end
