# What the student says about a place in the app (D-304). One append-only row; the state is derived from the
# events (CommentEvent). Read by the student (their own), the teacher's page and the console, never by the API and
# never by an agent (a minor's words).
class Comment < ApplicationRecord
  REASONS = %w[not_understood error not_working like other].freeze
  PAGE_KINDS = %w[today subjects subject topic lesson practice diagnosis warmup sitting results settings search comments].freeze
  # The states the student and the teacher read: new (sent), read, answered, closed. Derived, never stored.
  STATES = %w[sent read answered closed].freeze
  TEXT_MAX = 500
  SELECTED_MAX = 300

  belongs_to :student
  belongs_to :subject, optional: true
  belongs_to :topic_revision, optional: true
  belongs_to :lesson_revision, optional: true
  belongs_to :practice_serve, optional: true
  belongs_to :diagnosis_run, optional: true
  belongs_to :item_instance, optional: true
  belongs_to :item_revision, optional: true
  belongs_to :blueprint_revision, optional: true
  has_many :events, -> { order(:id) }, class_name: "CommentEvent", inverse_of: :comment

  # sent -> read -> answered -> closed; a reopened comment is back to where its replies put it.
  def state
    kinds = events.map(&:kind)
    return "closed" if kinds.reverse.find { |k| %w[resolved reopened].include?(k) } == "resolved"
    return "answered" if kinds.include?("reply")
    return "read" if kinds.include?("read")

    "sent"
  end

  def replies = events.select { |e| e.kind == "reply" }

  # A reply the student has not seen yet: a reply after the last reply_seen.
  def unread_reply?
    last_reply = events.select { |e| e.kind == "reply" }.map(&:id).max or return false
    last_seen = events.select { |e| e.kind == "reply_seen" }.map(&:id).max
    last_seen.nil? || last_seen < last_reply
  end

  def self.unread_reply_count(student)
    where(student: student).includes(:events).count(&:unread_reply?)
  end
end
