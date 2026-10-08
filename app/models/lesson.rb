# A lesson is the text of a topic and the topic's identity: its key is the topic key
# (ripasso|ponte|lezione).<subject>.<slug>. Immutable revisions hang off it (A7).
class Lesson < ApplicationRecord
  KINDS = %w[ripasso ponte lezione].freeze

  belongs_to :subject
  has_many :revisions, class_name: "LessonRevision"
  has_many :topic_revisions

  def latest_revision = revisions.max_by(&:seq)
end
