class Attempt < ApplicationRecord
  belongs_to :student
  belongs_to :served_event, class_name: "DiagnosisEvent", optional: true
  belongs_to :item_instance
  has_many :gradings, -> { order(:seq) }, class_name: "AttemptGrading"
end
