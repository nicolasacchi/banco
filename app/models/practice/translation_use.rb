module Practice
  # Where the student opened the Italian translation of an exercise of the english or spanish courses (D-402): the app events
  # `translation_opened` written by POST /translations (TranslationsController) that carry a serve_id. Informational only: no counter, not an aid,
  # nothing the engine or a skill state reads. The teacher reads it as the serve's `translations` (AttemptLog) and as «Traduzione aperta in N
  # esercizi su M» (PracticeProgress, TopicReview). Read-only.
  module TranslationUse
    KIND = "translation_opened".freeze

    Opening = Data.define(:scope, :at)

    module_function

    # {serve id => [Opening]} oldest first, for those serves (ids).
    def by_serve(serve_ids)
      ids = Array(serve_ids).uniq
      return {} if ids.empty?

      AppEvent.where(kind: KIND).where("json_extract(payload_json, '$.serve_id') IN (?)", ids).order(:id).each_with_object({}) do |event, all|
        payload = JSON.parse(event.payload_json || "{}")
        (all[payload["serve_id"]] ||= []) << Opening.new(payload["scope"], event.created_at)
      end
    end

    # [N, M]: in how many of these serves (exercises shown) the translation was opened, out of how many serves.
    # `openings`: the result of by_serve for a superset of the serves, when the caller asks for several groups.
    def count(serve_ids, openings = nil)
      ids = Array(serve_ids).uniq
      openings ||= by_serve(ids)
      [ ids.count { |id| openings.key?(id) }, ids.size ]
    end

    # «Traduzione aperta in N esercizi su M», or nil when it was opened in none.
    def line(serve_ids, openings = nil)
      opened, total = count(serve_ids, openings)
      I18n.t("teacher.translation.opened", count: opened, total: total, locale: :it) if opened.positive?
    end
  end
end
