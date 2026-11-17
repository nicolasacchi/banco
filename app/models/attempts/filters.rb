module Attempts
  # The filters of the student's attempts list (D-346), checked by Api::V1::AttemptsController. A source that cannot hold a filter has no
  # row for it (a lesson check has no skill, an entry-test answer no serve). since: a Time (at or after it); till: a Time (at or before
  # it); outcome: a string (the row's `outcome`); serve: a practice serve id; comment: a Comment (the tries behind it).
  Filters = Data.define(:subject, :topic, :skill, :item, :since, :till, :outcome, :serve, :comment) do
    def initialize(subject: nil, topic: nil, skill: nil, item: nil, since: nil, till: nil, outcome: nil, serve: nil, comment: nil) = super
  end
end
