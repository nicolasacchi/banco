# D-05: api_tokens carry a public id (8 characters) and the sha256 of the secret,
# and roles agent_claude | agent_omp | ci. M2 created the table before the token
# format was fixed; it holds no rows yet (tokens are issued by the operator with
# banco:token:issue), so it is recreated. The migration refuses to run over data.
class ReshapeApiTokens < ActiveRecord::Migration[8.1]
  ROLES = "role IN ('agent_claude','agent_omp','ci')".freeze

  def up
    %i[api_token_revocations api_tokens].each do |table|
      raise "#{table} holds rows; refusing to recreate it" if select_value("SELECT COUNT(*) FROM #{table}").to_i.positive?
    end
    drop_table :api_token_revocations
    drop_table :api_tokens

    create_table :api_tokens do |t|
      t.string :public_id, null: false, index: { unique: true }
      t.string :secret_sha256, null: false
      t.string :role, null: false
      t.string :label, null: false
      t.datetime :created_at, null: false
      t.check_constraint "length(public_id) = 8", name: "api_tokens_public_id_length"
      t.check_constraint "length(secret_sha256) = 64", name: "api_tokens_sha256_length"
      t.check_constraint ROLES, name: "api_tokens_role"
    end
    create_table :api_token_revocations do |t|
      t.references :api_token, null: false, foreign_key: true, index: { unique: true }
      t.string :reason
      t.datetime :created_at, null: false
    end
    %w[api_tokens api_token_revocations].each { |table| Banco::AppendOnly.install(connection, table) }
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
