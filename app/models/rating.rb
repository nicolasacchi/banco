# What the student thinks of an exercise or a lesson (D-365): 1 to 5 stars and a comment, both optional, one of them at least. One append-only row
# per rating; a later rating of the same target by the same student is a new row, and the current one is the latest (`current`). A target is
# an exercise (`item`, named by its item key and the item revision of the instance he was served, rated from a practice serve) or a `lesson`
# (the lesson key, which is the topic's key, and the lesson revision he was reading). The teacher only reads ratings (the page, the API for a
# bot_read or teacher token): no reply, no thread, no decision, and nothing an engine, a gate or a grade reads. Written by Ratings::Intake alone.
class Rating < ApplicationRecord
  KINDS = %w[item lesson].freeze
  LANGUAGES = %w[it en].freeze
  STARS = (1..5)
  TEXT_MAX = 2000

  belongs_to :student
  belongs_to :subject
  belongs_to :topic_revision
  belongs_to :item_revision, optional: true
  belongs_to :lesson_revision, optional: true
  belongs_to :practice_serve, optional: true

  # The average (of the current stars, trial students left out) and how many students it is made of; nil when there is none.
  Summary = Data.define(:count, :average) do
    # «4,2» for the teacher's pages (a comma), the number itself for the API.
    def average_it = format("%.1f", average).tr(".", ",")
  end

  scope :newest_first, -> { order(id: :desc) }
  scope :items, -> { where(target_kind: "item") }
  scope :lessons, -> { where(target_kind: "lesson") }
  scope :of_target, ->(key) { where(target_key: key) }
  scope :of_student, ->(key) { where(student_id: Student.where(key: key).select(:id)) }
  scope :of_subject, ->(key) { where(subject_id: Subject.where(key: key).select(:id)) }
  # A topic is its lesson's key: the topic revisions of that lesson.
  scope :of_topic, ->(key) { where(topic_revision_id: TopicRevision.where(lesson_id: Lesson.where(key: key).select(:id)).select(:id)) }
  scope :created_since, ->(time) { where(created_at: time..) }
  scope :official, -> { where(trial: false) }
  scope :trial, -> { where(trial: true) }
  # The latest rating of each student for each target, over every revision (the student's present opinion of that exercise or lesson).
  scope :current, -> { where(id: Rating.unscoped.group(:student_id, :target_kind, :target_key).select("MAX(ratings.id)")) }

  def item? = target_kind == "item"
  def lesson? = target_kind == "lesson"
  def revision_id = item? ? item_revision_id : lesson_revision_id

  # The student's latest rating of a target, or nil.
  def self.latest_for(student, kind, key)
    where(student_id: student.id, target_kind: kind, target_key: key).order(:id).last
  end

  # Summary of the current starred ratings of the official student(s) in this relation: trial students test the pages and never count.
  def self.summary(relation = all)
    count, average = relation.current.official.where.not(stars: nil).pick(Arel.sql("COUNT(*)"), Arel.sql("AVG(ratings.stars)"))
    count.to_i.positive? ? Summary.new(count: count.to_i, average: average.to_f) : nil
  end

  # { [kind, key] => Summary } for every target of the relation that has one.
  def self.summaries(relation = all)
    rows = relation.current.official.where.not(stars: nil).group(:target_kind, :target_key).pluck(:target_kind, :target_key, Arel.sql("COUNT(*)"), Arel.sql("AVG(ratings.stars)"))
    rows.to_h { |kind, key, count, average| [ [ kind, key ], Summary.new(count: count.to_i, average: average.to_f) ] }
  end
end
