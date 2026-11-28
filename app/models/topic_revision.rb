# Pins one lesson revision and, per skill, the practice item revisions (ids only). The
# teacher approves topic revisions. The topic is its lesson.
class TopicRevision < ApplicationRecord
  include Searchable

  belongs_to :lesson
  belongs_to :course_revision
  belongs_to :lesson_revision
  belongs_to :author_session, class_name: "AgentSession", optional: true

  def body = JSON.parse(body_json)

  # The writing tasks of the topic (D-407): [{"item" => key, "revision" => item revision id}], none for most topics. Never part of the practice.
  def writing_pins = Array(body["writing"])

  # Every item revision the topic pins: the exercises' and the writing tasks'. What the approval gate, the stale-pin check and the reviews read.
  def pinned_item_revision_ids = body["practice"].flat_map { |p| p["items"].map { |i| i["revision"] } } + writing_pins.map { |i| i["revision"] }
end
