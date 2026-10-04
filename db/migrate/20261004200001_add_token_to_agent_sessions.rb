# D-071: a session is bound to the API token that created it (the token's public id).
# Rows made before this column (tests, fixtures) have none and are not bound.
class AddTokenToAgentSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_sessions, :token_id, :string
  end
end
