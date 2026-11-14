# Created only by DecisionRecorder (D-08, later milestone); never by seeds.
class Decision < ApplicationRecord
  include Searchable

  # The decisions that change what a door may show (Search::Scope reads them at query time; the index only needs the statuses).
  SEARCH_KINDS = %w[approve_topic release_course approve_blueprint approve_skill_graph send_back_lesson send_back_item].freeze

  belongs_to :subject, optional: true
  belongs_to :student, optional: true

  # Recorded from the host console (bin/rails banco:decide), not in the browser (D-260).
  def console? = remote_addr == DecisionRecorder::Console::ADDR && groups == DecisionRecorder::Console::GROUP

  # Recorded over the API with a teacher token (D-327): the payload says via "api" and names the token.
  def api? = groups == DecisionRecorder::Api::GROUP

  # How it was recorded: "web" (the browser), "console" or "api" (the payload says so: D-260, D-327).
  def via = JSON.parse(payload_json)["via"].presence || "web"

  private

  def search_relevant? = SEARCH_KINDS.include?(kind)
end
