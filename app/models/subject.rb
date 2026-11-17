class Subject < ApplicationRecord
  has_many :items
  has_many :skill_graph_revisions
  has_many :blueprint_revisions

  # The name the student's school gives the subject (config/locales/subjects.it.yml, D-343), else the seed name of the
  # column: the table is append-only, so a school's name cannot be written over it. Every page, API and search text
  # reads the name here, never the column.
  def name_it = I18n.t("subjects.display_name_it.#{key}", default: self[:name_it])
end
