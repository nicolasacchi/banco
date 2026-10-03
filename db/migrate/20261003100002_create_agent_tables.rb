# Agent sessions, API tokens (with roles) and their revocations (E-09).
class CreateAgentTables < ActiveRecord::Migration[8.1]
  TABLES = %i[agent_sessions api_tokens api_token_revocations].freeze

  def change
    create_table :agent_sessions do |t|
      t.string :label, null: false
      t.string :role, null: false
      t.datetime :created_at, null: false
      t.check_constraint "role IN ('author','verifier','reviewer','solver','grader','operator')",
                         name: "agent_sessions_role"
    end

    # Only the digest of a token is stored. Revoking a token is a new row.
    create_table :api_tokens do |t|
      t.string :token_digest, null: false, index: { unique: true }
      t.string :role, null: false
      t.string :label, null: false
      t.datetime :created_at, null: false
      t.check_constraint "role IN ('author','verifier','reviewer','solver','grader','operator')",
                         name: "api_tokens_role"
    end

    create_table :api_token_revocations do |t|
      t.references :api_token, null: false, foreign_key: true, index: { unique: true }
      t.string :reason
      t.datetime :created_at, null: false
    end

    reversible do |dir|
      dir.up { TABLES.each { |table| Banco::AppendOnly.install(connection, table) } }
    end
  end
end
