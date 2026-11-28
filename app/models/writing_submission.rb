# A text the student wrote himself on a topic that pins a writing task (D-407): an Italian narrative or argumentative text, a Spanish biography, an English
# description. One append-only row per text sent; a new version is a new row. The teacher corrects it with the decision `correct_writing` (Writings::Corrections
# reads the latest of each), never with a column here. The text is the student's own words: never indexed by search, never read by an engine, a gate, a grade or
# the practice (a writing task is not an exercise). Written by Writings::Intake alone.
class WritingSubmission < ApplicationRecord
  TEXT_MAX = 4000
  # The teacher's correction (the decision's text_it): the text rewritten with her notes can be as long as the text and a few lines more.
  CORRECTION_MAX = 6000

  belongs_to :student
  belongs_to :topic_revision
  belongs_to :item_revision

  scope :newest_first, -> { order(id: :desc) }
  scope :of_student, ->(student) { where(student_id: student.id) }
  scope :of_item, ->(item) { where(item_revision_id: ItemRevision.where(item_id: item.id).select(:id)) }

  # The words of a text, as the browser counts them (a run of non-space characters).
  def self.count_words(text) = text.to_s.strip.split(/[[:space:]]+/).count(&:present?)

  # The text as it is stored: line breaks as \n, no space around it.
  def self.clean(text) = text.to_s.gsub("\r\n", "\n").strip

  def topic_key = topic_revision.lesson.key
  def item_key = item_revision.item.key
  def subject = topic_revision.lesson.subject
end
