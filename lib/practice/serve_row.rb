# frozen_string_literal: true

module Practice
  # One serve of a student with everything derived about it (loader output). status is a ServeState::Status.
  ServeRow = Data.define(:id, :student_id, :skill, :topic_revision_id, :item_instance_id, :item_revision_id, :item_id, :fingerprint,
                         :reason, :parent_serve_id, :error_code, :at, :hints_shown, :solution_requested, :status)
end
