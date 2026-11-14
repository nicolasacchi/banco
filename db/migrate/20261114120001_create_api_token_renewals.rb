# D-330: a public token renews itself on use. A renewal is a new row (firm rule 4: api_tokens stays append-only and its
# expires_at is never rewritten); a token's effective expiry is the latest of its own expires_at and of its renewals'
# (ApiToken#effective_expires_at). Written only by ApiToken#renew_on_use!, at most about one row per token per day.
class CreateApiTokenRenewals < ActiveRecord::Migration[8.1]
  def change
    create_table :api_token_renewals do |t|
      t.references :api_token, null: false, foreign_key: true, index: false
      t.datetime :expires_at, null: false
      t.datetime :created_at, null: false
      t.index %i[api_token_id expires_at]
      t.check_constraint "expires_at > created_at", name: "api_token_renewals_forward"
    end

    reversible do |dir|
      dir.up { Banco::AppendOnly.install(connection, :api_token_renewals) }
    end
  end
end
