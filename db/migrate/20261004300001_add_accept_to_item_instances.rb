# D-081: an instance may carry its own accepted spellings of the key (normalized_text).
# Rows made before this column have none.
class AddAcceptToItemInstances < ActiveRecord::Migration[8.1]
  def change
    add_column :item_instances, :accept_json, :text
  end
end
