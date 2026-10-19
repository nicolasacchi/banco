class BlindSolve < ApplicationRecord
  include ReadTimeIndependence

  belongs_to :item_revision
  belongs_to :agent_session
  has_many :findings, class_name: "ReviewFinding"

  def reviewed_thing = item_revision.item
end
