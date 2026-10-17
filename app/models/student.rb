class Student < ApplicationRecord
  # The official student's key: the one whose log is the diagnosis (D-217).
  OFFICIAL_KEY = "student".freeze
  # The key of the row the teacher's preview plays as; never a login's student key.
  PREVIEW_KEY = "preview".freeze
  KEY_FORMAT = /\A[a-z0-9-]+\z/

  # A trial student is an adult testing the student's pages: same engine, own log, results that do not count.
  def trial? = kind == "student" && key != OFFICIAL_KEY

  def official? = kind == "student" && key == OFFICIAL_KEY

  # The teacher's preview student of the course and the entry test (D-309). A reset starts a new one (the ledger is
  # append-only): its key is "preview.N", which no login can be mapped to (KEY_FORMAT has no dot).
  def preview? = kind == "preview"

  # The preview student in use: the latest of kind preview, made on first use.
  def self.current_preview
    where(kind: "preview").order(:id).last || create_with(kind: "preview").find_or_create_by!(key: PREVIEW_KEY)
  end

  # "Ricomincia da capo": a new preview student with no rows. The old one's rows stay (no UPDATE, no DELETE).
  def self.reset_preview!
    n = where(kind: "preview").count + 1
    create!(key: "#{PREVIEW_KEY}.#{n}", kind: "preview")
  end

  # The official student and the trial students (never the preview row), the official one first.
  def self.real # an Array
    where(kind: "student").order(:key).sort_by { |s| [ s.official? ? 0 : 1, s.key ] }
  end

  # The official student's row, or nil before the first login.
  def self.official = find_by(key: OFFICIAL_KEY, kind: "student")
end
