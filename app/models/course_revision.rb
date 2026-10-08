# One revision of a subject's course map (banco.course/1): seconda skills and ordered topics.
class CourseRevision < ApplicationRecord
  belongs_to :subject
  belongs_to :skill_graph_revision
  belongs_to :author_session, class_name: "AgentSession", optional: true
  has_many :topic_revisions

  def body = JSON.parse(body_json)
  def warnings = JSON.parse(warnings_json)
end
