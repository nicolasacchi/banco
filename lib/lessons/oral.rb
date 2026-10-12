# frozen_string_literal: true

module Lessons
  # The oral block (WAVE2 2.10) as the check endpoint sees it: its outline is an ordering. The answer, the typical errors and the model
  # answer stay on the server; the student's page gets the outline tiles shuffled (Diagnosis::Rekey ids e1..eN) and, after the outline is
  # right or the second try, the model answer in the reply (L6, x-banco-withheld).
  module Oral
    module_function

    # The ordering check that grades +block+'s outline (the shape Lessons::Checks reads); "model_it" rides on it so the endpoint can answer with it.
    def check(block)
      { "component" => "ordering", "items" => block["outline"], "answer" => block["answer"], "errors" => block["errors"].to_a, "model_it" => block["model_it"] }
    end
  end
end
