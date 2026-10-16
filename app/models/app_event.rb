class AppEvent < ApplicationRecord
  include Searchable

  belongs_to :student, optional: true

  private

  # The refused texts are searched by the teacher (D-298); no other event matters to the search.
  def search_relevant? = %w[invalid_input practice_invalid_input].include?(kind)
end
