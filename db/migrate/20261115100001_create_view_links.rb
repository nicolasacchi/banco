# D-332: a view link is a temporary URL that opens the teacher's pages read-only (the guest role) without login. The ledger
# is three append-only tables (firm rule 4): the link (only the sha256 of its token), each redemption, each revocation.
# A link's state (active, expired, revoked) is derived, never written: see ViewLinks.
class CreateViewLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :view_links do |t|
      t.references :api_token, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.string :path, null: false
      t.datetime :expires_at, null: false
      t.datetime :created_at, null: false
      t.index :token_digest, unique: true
      t.check_constraint "expires_at > created_at", name: "view_links_forward"
    end

    create_table :view_link_redemptions do |t|
      t.references :view_link, null: false, foreign_key: true
      t.datetime :created_at, null: false
    end

    create_table :view_link_revocations do |t|
      t.references :view_link, null: false, foreign_key: true, index: { unique: true }
      t.references :api_token, null: true, foreign_key: true, index: false
      t.datetime :created_at, null: false
    end

    reversible do |dir|
      dir.up { %i[view_links view_link_redemptions view_link_revocations].each { |table| Banco::AppendOnly.install(connection, table) } }
    end
  end
end
