# One working session of an agent (A-04): declared role, agent and model. Created by
# `banco session new`; the CLI sends its id in X-Banco-Session on every write. The
# server uses it to keep the author, the verifier, the reviewer, the blind solver and the
# arbiter (the third reviewer, D-222) of an item apart (ItemSessions) and the grader off the author's items. Rows are
# never changed.
class AgentSession < ApplicationRecord
  ROLES = %w[author verifier reviewer solver grader arbiter].freeze
  # The ids of file_sessions and the header are plain integers.
  ID = /\A[1-9]\d{0,17}\z/

  validates :role, inclusion: { in: ROLES }
  has_many :corrections, class_name: "AgentSessionCorrection"

  validates :agent, :model, presence: true, on: :create, if: -> { agent_declared? }

  # What the session declared (banco session new --model), never changed.
  def declared_model = self[:model]

  # The latest correction (D-316), or nil.
  def correction = corrections.loaded? ? corrections.max_by(&:id) : corrections.order(:id).last

  def corrected? = !correction.nil?

  # The TRUE model: the model of the latest correction, else the declared one. Every reader of a session's model
  # uses this one (independence, the arbiter, the teacher's pages); declared_model is only for showing the difference.
  def model = correction&.model || declared_model

  # The model family of config/banco/providers.yml, of the true model.
  def family = Providers.family(model)

  def to_h = { id: id, role: role, agent: agent, model: model, family: family }.merge(corrected? ? { declared_model: declared_model } : {})

  private

  # Rows made by older code (tests, fixtures) declare nothing; new sessions made
  # through the API always do.
  def agent_declared? = agent.present? || model.present?
end
