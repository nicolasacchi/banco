class Subject < ApplicationRecord
  has_many :items
  has_many :skill_graph_revisions
  has_many :blueprint_revisions
end
