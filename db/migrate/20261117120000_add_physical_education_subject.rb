# D-344: Scienze motorie, a twelfth subject (theory and exercises only; no entry test, so no blueprint). `subjects` is append-only
# (triggers block UPDATE and DELETE), but an insert is allowed: a database that already has the eleven gets the twelfth here, a fresh
# one gets it from db/seeds.rb (the same row). Idempotent: nothing is inserted when the key is there.
class AddPhysicalEducationSubject < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      INSERT INTO subjects (key, name_it, position, created_at)
      SELECT 'physical_education', 'Scienze motorie', 12, #{quote(connection.quoted_date(Time.current))}
      WHERE NOT EXISTS (SELECT 1 FROM subjects WHERE key = 'physical_education')
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "subjects is append-only: a subject is never deleted"
  end
end
