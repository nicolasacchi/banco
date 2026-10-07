module Diagnosis
  # The formula sheet as a declared support (D-216). The entry test (banco.blueprint/1) may carry
  # `formula_sheet_it`; the teacher switches it on for a subject with the decision `set_formula_sheet`
  # (default off). A run offers it when the decision is on and the blueprint the run is pinned to has one.
  # What was offered is written with each served item (item_served.formula_sheet_available); every opening
  # is an app_event `formula_sheet_opened` tied to the run and the served item. The engine never reads
  # any of this: the evidence is unchanged, the report marks it (Diagnosis::Report).
  module FormulaSheet
    OPENED = "formula_sheet_opened".freeze
    HELP_OPENED = "help_opened".freeze

    module_function

    # The sheet's text in a blueprint revision, or nil.
    def text(blueprint_revision)
      return nil unless blueprint_revision

      JSON.parse(blueprint_revision.body_json)["formula_sheet_it"].to_s.strip.presence
    end

    # The latest decision of the subject says on. Default off.
    def enabled?(subject)
      decision = Decision.where(subject: subject, kind: "set_formula_sheet").order(:id).last or return false
      JSON.parse(decision.payload_json)["enabled"] == true
    end

    def available_for_run?(run) = enabled?(run.subject) && !text(run.blueprint_revision).nil?

    # What a served item offered: the sheet's text when its row says it was available.
    def text_for_served(served, run)
      served.formula_sheet_available ? text(run.blueprint_revision) : nil
    end

    # The blueprint the decision is about: the approved one, else the latest draft.
    def target_blueprint(subject) = SubjectStage.approved_blueprint(subject) || Conductor.latest_blueprint(subject)

    # served_event_ids (diagnosis_events.id) the student opened the sheet on.
    def opened_serves(student)
      AppEvent.where(kind: OPENED, student_id: student.id).pluck(:payload_json).filter_map { |j| JSON.parse(j)["served_event_id"] }.to_set
    end
  end
end
