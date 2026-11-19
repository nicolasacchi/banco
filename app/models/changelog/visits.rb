module Changelog
  # When the student last opened «Novità» (D-375): the append-only app event `changelog_viewed`, one row per visit, no table of its own. What is
  # newer than that is new to him; before his first visit, what is newer than his account. The teacher's preview records nothing and has no dot.
  module Visits
    KIND = "changelog_viewed".freeze

    module_function

    # The moment of the last visit, else the moment his account began: nothing was «new» to a student who has never been told anything.
    def last_seen(student) = AppEvent.where(kind: KIND, student_id: student.id).maximum(:created_at) || student.created_at

    def visited?(student) = AppEvent.exists?(kind: KIND, student_id: student.id)

    # One row for this visit; `new` is how many things were new when he came.
    def record!(student, new_count:)
      AppEvent.create!(kind: KIND, student: student, payload_json: { new: new_count }.to_json)
    end
  end
end
