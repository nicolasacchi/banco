# What a student has typed in a practice serve and not answered (D-337): append-only, the latest row of a serve is its draft, a raw of "" clears it.
# Never graded, never a try. The serve body gives it back only while it is newer than the serve's last try.
class PracticeDraft < ApplicationRecord
  MAX_RAW = 20_000
  MAX_SOURCE = 32

  belongs_to :student
  belongs_to :practice_serve

  # The row that is the serve's draft now: the latest one, if newer than the serve's last try (a try answers what was typed); nil otherwise.
  def self.current_for(serve)
    latest = where(practice_serve_id: serve.id).order(:id).last or return nil
    last_try = PracticeAttempt.where(practice_serve_id: serve.id).maximum(:answered_at)
    last_try && latest.created_at <= last_try ? nil : latest
  end

  # The serve id => the draft text, for the serves with a non-empty current draft.
  def self.texts_for(serve_ids)
    return {} if serve_ids.empty?

    last_try = PracticeAttempt.where(practice_serve_id: serve_ids).group(:practice_serve_id).maximum(:answered_at)
    latest = where(id: where(practice_serve_id: serve_ids).group(:practice_serve_id).select("MAX(id)")).to_a
    latest.each_with_object({}) do |row, all|
      tried = last_try[row.practice_serve_id]
      all[row.practice_serve_id] = row.raw if row.raw != "" && !(tried && row.created_at <= tried)
    end
  end
end
