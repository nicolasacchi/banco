# More provenance on a decision (D-08): the teacher's groups, the browser and the
# path of the request, so the nightly reconciliation can match a row to a proxy
# log line. New columns only; the ledger triggers stay as they are.
class AddDecisionProvenance < ActiveRecord::Migration[8.1]
  def change
    add_column :decisions, :groups, :string, null: false, default: ""
    add_column :decisions, :user_agent, :string, null: false, default: ""
    add_column :decisions, :request_path, :string, null: false, default: ""
  end
end
