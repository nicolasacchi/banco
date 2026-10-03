# One working session of an agent (A-04): declared role, agent and model. Created by
# `banco session new`; the CLI sends its id in X-Banco-Session on every write. The
# server uses it to keep the author, the verifier, the reviewer and the blind solver
# of an item apart (ItemSessions) and the grader off the author's items. Rows are
# never changed.
class AgentSession < ApplicationRecord
  ROLES = %w[author verifier reviewer solver grader].freeze
  # The ids of file_sessions and the header are plain integers.
  ID = /\A[1-9]\d{0,17}\z/

  validates :role, inclusion: { in: ROLES }
  validates :agent, :model, presence: true, on: :create, if: -> { agent_declared? }

  # The model family of config/banco/providers.yml.
  def family = Providers.family(model)

  def to_h = { id: id, role: role, agent: agent, model: model, family: family }

  private

  # Rows made by older code (tests, fixtures) declare nothing; new sessions made
  # through the API always do.
  def agent_declared? = agent.present? || model.present?
end
