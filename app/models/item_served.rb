class ItemServed < ApplicationRecord
  self.table_name = "item_served"

  belongs_to :diagnosis_event
  belongs_to :item_instance
end
