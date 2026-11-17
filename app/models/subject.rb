class Subject < ApplicationRecord
  has_many :items
  has_many :skill_graph_revisions
  has_many :blueprint_revisions

  # The subjects with no entry test (D-344): theory only, no blueprint, never a test to take. They are left out of what counts the
  # entry test (the release of the diagnosis, the report of all subjects) and the teacher's pages say so instead of "to write".
  WITHOUT_ENTRY_TEST = %w[physical_education].freeze

  def self.with_entry_test = where.not(key: WITHOUT_ENTRY_TEST)

  def entry_test? = WITHOUT_ENTRY_TEST.exclude?(key)

  # The name the student's school gives the subject (config/locales/subjects.it.yml, D-343), else the seed name of the
  # column: the table is append-only, so a school's name cannot be written over it. Every page, API and search text
  # reads the name here, never the column.
  def name_it = I18n.t("subjects.display_name_it.#{key}", default: self[:name_it])
end
