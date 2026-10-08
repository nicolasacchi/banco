# frozen_string_literal: true

module Practice
  # The state-machine view of a try: its number and outcome.
  ServeTry = Data.define(:try_number, :outcome)
end
