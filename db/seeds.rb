# Production seeds: generic, idempotent, and never decisions, approvals or attempts
# (D-08). The log is append-only, so a seed inserts what is missing and never
# updates. Programmes are NOT seeded: the operator imports both with
# bin/rails banco:syllabus:import (public-repository hygiene, D-022).
require "digest"
require "yaml"

subjects = [
  [ "math", "Matematica" ],
  [ "italian", "Italiano" ],
  [ "english", "Inglese" ],
  [ "spanish", "Spagnolo" ],
  [ "history", "Storia" ],
  [ "geography", "Geografia" ],
  [ "law_economics", "Diritto ed economia" ],
  [ "business", "Economia aziendale" ],
  [ "computer_science", "Informatica" ],
  [ "biology", "Biologia" ],
  [ "chemistry", "Chimica" ]
].freeze

subjects.each_with_index do |(key, name_it), index|
  Subject.create_with(name_it: name_it, position: index + 1).find_or_create_by!(key: key)
end

# The one student and the teacher's preview student (tentativi teacher_preview).
Student.create_with(kind: "student").find_or_create_by!(key: "student")
Student.create_with(kind: "preview").find_or_create_by!(key: "preview")

# Constitution, arts. 1-12: public-domain text with its source and sha256.
costituzione = Rails.root.join("db/syllabus/costituzione-artt-1-12.md")
provenance = YAML.safe_load_file(Rails.root.join("db/syllabus/costituzione-artt-1-12.source.yml"))
body = costituzione.read
unless Digest::SHA256.hexdigest(body) == provenance.fetch("sha256")
  raise "costituzione-artt-1-12.md does not match its recorded sha256"
end
ReferenceText.create_with(
  title: "Costituzione, principi fondamentali (artt. 1-12)",
  source_url: provenance.fetch("source_url"), sha256: provenance.fetch("sha256"), body: body
).find_or_create_by!(key: "costituzione-artt-1-12")
