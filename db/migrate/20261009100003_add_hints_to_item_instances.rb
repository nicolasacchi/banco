# Phase 1b (S1): the effective hints of a practice instance (its own hints_it, else the
# item's), as the student reads them on request. Null for every other instance. The text is
# stored apart from display_json so no display ever carries a hint (the blind solver and the
# student's page read display only). The triggers of the table stay in place.
class AddHintsToItemInstances < ActiveRecord::Migration[8.1]
  def change
    add_column :item_instances, :hints_json, :text
  end
end
