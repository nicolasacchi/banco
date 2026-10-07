# D-216: whether the declared formula sheet was available when the item was served. Written
# once with the row (the ledger is append-only); rows made before it were served without one.
class AddFormulaSheetToItemServed < ActiveRecord::Migration[8.1]
  def change
    add_column :item_served, :formula_sheet_available, :boolean, default: false, null: false
  end
end
