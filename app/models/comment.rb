# What the student says about a place in the app (D-304). One append-only row; the state is derived from the
# events (CommentEvent). Read by the student (their own), the teacher's page and the console and, since D-327, over the
# API by a bot_read or teacher token (Api::V1::CommentsController); never by a content agent's token (a minor's words).
class Comment < ApplicationRecord
  REASONS = %w[not_understood error not_working like other].freeze
  PAGE_KINDS = %w[today subjects subject topic lesson practice diagnosis warmup sitting results settings search comments].freeze
  # The states the student and the teacher read: new (sent), read, answered, closed. Derived, never stored.
  STATES = %w[sent read answered closed].freeze
  MESSAGE_KINDS = %w[reply student_reply].freeze
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

  # One message of the conversation: from :student or :teacher, the text (the first one may have none), the event
  # (nil for the comment itself) and the time.
  Message = Struct.new(:from, :text_it, :event, :at, keyword_init: true)

  # The conversation in order (D-342): the student's comment, then the teacher's replies and the student's follow-ups
  # (student_reply) in id order.
  def thread
    first = Message.new(from: :student, text_it: text_it, event: nil, at: created_at)
    [ first ] + events.select { |e| MESSAGE_KINDS.include?(e.kind) }.map { |e| Message.new(from: e.kind == "reply" ? :teacher : :student, text_it: e.text_it, event: e, at: e.created_at) }
  end

  # sent -> read -> answered -> closed; a reopened comment is back to where its replies put it. A follow-up of the
  # student after a resolved reopens the comment like a reopened (D-342). When the latest message of the thread is the
  # student's follow-up, the comment waits for the teacher again: sent, or read once the teacher has marked it read after it.
  def state
    list = events.to_a
    return "closed" if list.reverse.find { |e| %w[resolved reopened student_reply].include?(e.kind) }&.kind == "resolved"

    last_message = list.reverse.find { |e| MESSAGE_KINDS.include?(e.kind) }
    return (list.any? { |e| e.kind == "read" && e.id > last_message.id } ? "read" : "sent") if last_message&.kind == "student_reply"
    return "answered" if list.any? { |e| e.kind == "reply" }
    return "read" if list.any? { |e| e.kind == "read" }

    "sent"
  end

  # When the student last wrote: the latest follow-up, else the comment itself (the teacher's inbox sorts on it, so a
  # follow-up on an old comment comes back to the top).
  def last_student_message_at = thread.reverse.find { |m| m.from == :student }.at

  def replies = events.select { |e| e.kind == "reply" }

  def student_replies = events.select { |e| e.kind == "student_reply" }

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
