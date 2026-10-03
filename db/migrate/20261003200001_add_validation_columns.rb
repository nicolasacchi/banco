# M5: what validation needs to remember and the tables could not hold yet.
#
# item_revisions.files_json: the revision's other files {name => text}
# (generator.mjs, verify.mjs, assets/*), so the harness can serve them to Chrome
# and a later revision can carry them forward. item.json stays in body_json.
#
# item_validations: the versions a verdict was made under (A-06, A-07) and every
# finding, warnings included, as JSON. codes_json keeps the E- codes only.
class AddValidationColumns < ActiveRecord::Migration[8.1]
  def change
    add_column :item_revisions, :files_json, :text

    change_table :item_validations do |t|
      t.text :findings_json
      t.string :rules_version
      t.string :grader_version
      t.string :harness_version
      t.string :chrome_version
      t.string :instances_sha256, limit: 64
      t.integer :attempt
    end
  end
end
