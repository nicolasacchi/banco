# Created only by DecisionRecorder (D-08, later milestone); never by seeds.
class Decision < ApplicationRecord
  belongs_to :subject, optional: true
  belongs_to :student, optional: true
end
