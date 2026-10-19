# A correction of the model a session declared (D-316), append-only. The true model of a session is the model of its
# latest correction (AgentSession#model); the declared one stays readable (AgentSession#declared_model). Written only
# by the host console (AgentSessionCorrector, bin/rails banco:correct_session): no route, no API, no CLI command.
class AgentSessionCorrection < ApplicationRecord
  belongs_to :agent_session

  validates :model, :reason, :request_id, presence: true
end
