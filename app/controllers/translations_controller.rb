# The student opened the Italian translation of a card, a block, an exercise or a list page of the english or spanish courses (D-402): one
# AppEvent `translation_opened`, informational only (no counter, not an aid, nothing the engine reads). POST /translations, student only
# (official and trial); a guest and the teacher get 403 and no row; the teacher's preview answers 204 and writes nothing (it reads the
# translation always open). The body is JSON from items/translation.js:
#   { "surface": "lesson"|"practice"|"topics", "scope": "card"|"block"|"item"|"page", "topic"?: key, "card"?: n, "block"?: n, "serve_id"?: n }
# Anything else in it, or a member of the wrong shape, is a 422 and no row. 204 with no body on success.
class TranslationsController < ApplicationController
  include ActingStudent

  wrap_parameters false

  KIND = "translation_opened".freeze
  SURFACES = %w[lesson practice topics].freeze
  SCOPES = %w[card block item page].freeze
  TOPIC = /\A(ripasso|ponte|lezione|extra)\.[a-z_]+\.[a-z0-9]+(-[a-z0-9]+)*\z/
  NUMBERS = %w[card block serve_id].freeze
  MAX_NUMBER = 2_000_000_000

  def create
    body = parsed
    return head(:unprocessable_entity) unless body
    return head(:no_content) if preview?

    AppEvent.create!(kind: KIND, student: acting_student, payload_json: body.to_json)
    head :no_content
  end

  private

  # The event's payload, or nil when the request body is not what the browser sends.
  def parsed
    raw = request.request_parameters
    return nil unless raw.is_a?(Hash) && SURFACES.include?(raw["surface"]) && SCOPES.include?(raw["scope"])
    return nil unless (raw.keys - %w[surface scope topic card block serve_id]).empty?
    return nil if raw.key?("topic") && !(raw["topic"].is_a?(String) && raw["topic"].match?(TOPIC))
    return nil unless NUMBERS.all? { |key| !raw.key?(key) || number?(raw[key]) }

    raw.slice("surface", "scope", "topic", *NUMBERS)
  end

  def number?(value) = value.is_a?(Integer) && value.between?(1, MAX_NUMBER)
end
