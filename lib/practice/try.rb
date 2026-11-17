# frozen_string_literal: true

module Practice
  # One graded try of a practice serve, as the fold reads it (A8.5). day is a calendar date in
  # Europe/Rome computed by the loader; the fold never touches a zone. evidence is :C, :W or :N.
  # aided includes the serve's reason reseen (the loader also sets reseen on its own). contested: the student sent the
  # try to the teacher; its outcome is then :contested and its evidence :N (practice/3).
  Try = Data.define(:skill, :at, :day, :serve_id, :fingerprint, :item_id, :item_revision_id, :low_guess, :try_number,
                    :aided, :reseen, :evidence, :outcome, :error_codes, :seconds, :contested) do
    def initialize(contested: false, **rest) = super
  end
end
