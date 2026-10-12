# Created only by DecisionRecorder (D-08, later milestone); never by seeds.
class Decision < ApplicationRecord
  belongs_to :subject, optional: true
  belongs_to :student, optional: true

  # Recorded from the host console (bin/rails banco:decide), not in the browser (D-260).
  def console? = remote_addr == DecisionRecorder::Console::ADDR && groups == DecisionRecorder::Console::GROUP
end
