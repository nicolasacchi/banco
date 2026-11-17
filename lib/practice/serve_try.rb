# frozen_string_literal: true

module Practice
  # The state-machine view of a try: its number and outcome. contested: the student sent it to the teacher
  # («Fai controllare»); the loader then gives it the outcome :contested too.
  ServeTry = Data.define(:try_number, :outcome, :contested) do
    def initialize(try_number:, outcome:, contested: false) = super
  end
end
