module Diagnosis
  # What one request (or job, or test) has already read from the diagnosis ledger, so that a page asking the
  # same question many times reads once: the plan and the events of a run, what a run derives to on its own.
  # A page that lists eleven subjects used to load the plan of every run once for every subject.
  #
  # The memo is only ever right: it is thrown away the moment a row that the loaders read is added (the ledger is
  # append-only, so the largest id of each such table says whether anything new is there). One query reads the
  # largest ids; inside a request the query cache answers it until a write. `CurrentAttributes` empties it at the
  # end of every request, job and test.
  #
  #   Diagnosis::Reads.fetch(:plan, run.id, true) { ... }   # the block runs once while the ledger stands still
  class Reads < ActiveSupport::CurrentAttributes
    attribute :store

    # Every table whose rows PlanLoader or EventLoader read for a run: the runs and their events, the attempts and
    # their gradings, the teacher's decisions, the retry exhaustions, the validation verdicts that say which
    # items are served and the skill graphs that foreign skills come from. (Revisions, instances and the served
    # detail rows are immutable once a run points at them.)
    VERSION_SQL = <<~SQL.squish.freeze
      SELECT (SELECT MAX(id) FROM diagnosis_runs), (SELECT MAX(id) FROM diagnosis_events), (SELECT MAX(id) FROM attempts),
             (SELECT MAX(id) FROM attempt_gradings), (SELECT MAX(id) FROM decisions),
             (SELECT MAX(id) FROM app_events WHERE kind = 'grade_retries_exhausted'),
             (SELECT MAX(id) FROM item_validations), (SELECT MAX(id) FROM skill_graph_revisions)
    SQL

    def self.fetch(*key)
      version = ApplicationRecord.connection.select_rows(VERSION_SQL).first
      current = store
      current = self.store = { version: version, values: {} } unless current && current[:version] == version
      current[:values].fetch(key) { current[:values][key] = yield }
    end
  end
end
