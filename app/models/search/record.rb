module Search
  # The content search index lives in its own SQLite file (config/database.yml, `search`): derived from the
  # primary database, disposable, rebuilt by `bin/rails banco:search:rebuild`. It has no append-only triggers and
  # no Rails migrations: its schema is Search::Schema (a version in PRAGMA user_version).
  class Record < ActiveRecord::Base
    self.abstract_class = true
    connects_to database: { writing: :search, reading: :search }
  end
end
