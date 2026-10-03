class DiagnosisRun < ApplicationRecord
  belongs_to :student
  belongs_to :subject
  belongs_to :blueprint_revision
  has_many :events, class_name: "DiagnosisEvent"
end
