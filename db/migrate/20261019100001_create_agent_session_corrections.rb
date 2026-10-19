# The correction line of a session's model (D-316). A session declares its model (banco session new --model) and
# nobody can prove it; when the operator learns that a declaration was false, the ledger stays append-only
# (firm rule 4) and the correction is a new row. The true model of a session is the model of its latest
# correction, else the declared one (AgentSession#model); the declared one stays readable (declared_model).
# Written only by the host console (bin/rails banco:correct_session); the origin columns follow the console
# decisions (D-260). No route, no API, no CLI command writes it.
class CreateAgentSessionCorrections < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_session_corrections do |t|
      t.references :agent_session, null: false, foreign_key: true
      t.string :model, null: false
      t.text :reason, null: false
      t.string :os_user, null: false, default: ""
      t.string :groups, null: false, default: "console"
      t.string :remote_addr, null: false, default: "console"
      t.string :user_agent, null: false, default: ""
      t.string :request_path, null: false, default: ""
      t.string :request_id, null: false
      t.datetime :created_at, null: false
      t.index %i[agent_session_id id]
      t.index :request_id, unique: true
      t.check_constraint "length(trim(model)) > 0", name: "agent_session_corrections_model"
      t.check_constraint "length(trim(reason)) BETWEEN 3 AND 1000", name: "agent_session_corrections_reason"
    end

    reversible do |dir|
      dir.up { Banco::AppendOnly.install(connection, :agent_session_corrections) }
    end
  end
end
