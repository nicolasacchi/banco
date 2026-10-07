module Diagnosis
  # The two interface events of the supports (D-216), both app_events, never run events:
  #
  #   help_opened          the student opened "Come si risponde" on a served item; payload: component.
  #                        Interface help only: nothing the engine, the grader or the report reads.
  #   formula_sheet_opened the student opened the "Formulario" on a served item; one row per opening.
  #                        Refused when the item was served without the sheet.
  #
  # Both are tied to the run and the served item (served_event_id is the item_served event).
  module SupportEvents
    KINDS = [ FormulaSheet::HELP_OPENED, FormulaSheet::OPENED ].freeze
    COMPONENTS = %w[number fraction expression choice ordering matching normalized_text short_answer testlet].freeze

    module_function

    # :ok, :not_found (unknown kind, or a serve that is not this run's) or :unavailable (no sheet on that serve).
    def record(run:, student:, kind:, served_event_id:, component: nil)
      return :not_found unless KINDS.include?(kind)

      event = run.events.find_by(id: served_event_id, kind: "item_served") or return :not_found
      served = ItemServed.find_by(diagnosis_event_id: event.id) or return :not_found
      payload = { run_id: run.id, served_event_id: event.id }
      if kind == FormulaSheet::OPENED
        return :unavailable unless served.formula_sheet_available
      else
        payload[:component] = COMPONENTS.include?(component.to_s) ? component.to_s : "unknown"
      end
      AppEvent.create!(kind: kind, student: student, payload_json: payload.to_json)
      :ok
    end
  end
end
