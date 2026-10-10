# One thing the student did in a lesson/2 (A11): a card seen, a check answered. Append-only (firm rule 4), apart from
# practice_events. Nothing here counts for a skill state: no practice, diagnosis or skill-state read model reads
# this table (a test pins it).
class LessonEvent < ApplicationRecord
  # Release 1 writes the first two; the others have their writer in 1.1 or 2 and are in the CHECK from the start.
  KINDS = %w[card_seen check_answered more_opened steps_shown lesson_printed page_opened page_event page_failed].freeze
  WRITTEN_BY_BATCH = %w[card_seen].freeze
  ID_FORMAT = /\A[A-Za-z0-9_-]{8,64}\z/
  # One card_seen per card per window (A11).
  SEEN_WINDOW = 10.minutes

  belongs_to :student
  belongs_to :topic_revision
  belongs_to :lesson_revision

  def payload = JSON.parse(payload_json)
end
