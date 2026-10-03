class BlindSolve < ApplicationRecord
  belongs_to :item_revision
  belongs_to :agent_session
  has_many :findings, class_name: "ReviewFinding"
end
