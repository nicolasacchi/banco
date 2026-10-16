# One thing that happened to a comment: reply, read, resolved, reopened, sent_back (C2) by the teacher (web) or
# the operator's console, reply_seen by the student. Append-only (triggers).
class CommentEvent < ApplicationRecord
  KINDS = %w[reply read resolved reopened sent_back reply_seen].freeze
  TEACHER_KINDS = %w[reply read resolved reopened].freeze
  REPLY_MAX = 2000

  belongs_to :comment
end
