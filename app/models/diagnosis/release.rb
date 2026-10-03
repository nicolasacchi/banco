module Diagnosis
  # Has the teacher opened the diagnosis? The decision release_diagnosis (D-002,
  # all subjects together) is recorded by the teacher's side (M9); until a row of
  # that kind exists the student sees only the warm-up and one line.
  module Release
    module_function

    def open? = Decision.where(kind: "release_diagnosis").exists?
  end
end
