# The student's search (D-299): lessons by card, glossary terms, topics and the exercises of the courses open to this student.
#
# Lexical only and with no model in the way (firm rule 1): this controller and everything it calls never touch an embedding
# client. The words typed are not stored anywhere: no app event, no table, no cache; `q` is filtered from the request log.
# What is found is decided by Search::Scope::Student (the same catalog as the course pages), at the moment of the question.
class SearchController < ApplicationController
  include ActingStudent

  MAX_QUERY = 120
  LIMIT = 30

  before_action :no_store

  def show
    @query = params[:q].to_s.squish.first(MAX_QUERY)
    @scope = Search::Scope::Student.for(acting_student)
    @result = Search::Engine.new(scope: @scope).call(@query, limit: LIMIT) if @query.present?
    @groups = grouped(@result.hits) if @result
    response.headers["Referrer-Policy"] = "no-referrer"
  end

  private

  ORDER = %w[topic lesson_card glossary_term practice_item].freeze

  # [[kind, [hit]]] in the order a student reads them, only the kinds that have hits.
  def grouped(hits)
    hits.group_by(&:kind).sort_by { |kind, _| ORDER.index(kind) || ORDER.size }
  end
end
