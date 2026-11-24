# A try the student sent to the teacher with «Fai controllare» (D-339): append-only, one row per attempt. The row's existence is what makes the try
# `contested` (Practice::Loader reads it); the attempt and its grading stay as they were. comment_id is nil since D-400 (the teacher reads the contest in
# «Contestazioni», no comment is written); the older rows keep the comment they were written with.
class PracticeContest < ApplicationRecord
  belongs_to :student
  belongs_to :practice_serve
  belongs_to :practice_attempt
  belongs_to :comment, optional: true
end
