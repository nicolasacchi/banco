# A try the student sent to the teacher with «Fai controllare» (D-339): append-only, one row per attempt. The row's existence is what makes the try
# `contested` (Practice::Loader reads it); the attempt and its grading stay as they were. comment_id is the comment the teacher reads (nil in the
# teacher's preview, which never writes comments, D-309).
class PracticeContest < ApplicationRecord
  belongs_to :student
  belongs_to :practice_serve
  belongs_to :practice_attempt
  belongs_to :comment, optional: true
end
