# The first time a student had no unseen exercise left on a skill of a topic revision (D-348, practice/5): append-only, one row per student, topic
# revision and skill. The selector records it and serves nothing on its own; the teacher's practice page and the practice progress API read it.
class PracticePoolExhaustion < ApplicationRecord
  belongs_to :student
  belongs_to :topic_revision

  # Records the fact once: a second call, a second tab or a retry find the row and add none. Call inside the serving transaction.
  def self.record!(student:, topic_revision:, skill_key:, now: Time.current)
    find_or_create_by!(student_id: student.id, topic_revision_id: topic_revision.id, skill_key: skill_key) { |row| row.created_at = now }
  end

  # {skill key => the first time (UTC Time) the student ran out of unseen exercises on it, in any topic revision}.
  def self.first_by_skill(student, skill_keys)
    where(student_id: student.id, skill_key: skill_keys).group(:skill_key).minimum(:created_at)
  end
end
