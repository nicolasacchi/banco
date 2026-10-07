module Teacher
  # The report of a subject (B-09): the same hash as `banco diagnosis report`, with the
  # student's example answers, and the teacher's four controls on a run.
  class ReportsController < Teacher::BaseController
    def show
      subject! or return
      @unit = "#{@subject.key}:report"
      @report = Diagnosis::Report.call(subject: @subject, with_answers: true, student: viewed_student)
      @row = @report[:subjects].first
      @revisions = revisions_of_run
    end

    private

    # The item revisions the student has answered in this subject, for "Annulla i tentativi".
    def revisions_of_run
      run_id = @row.dig(:run, :id) or return []
      served = ItemServed.joins(:diagnosis_event).where(diagnosis_events: { diagnosis_run_id: run_id }).includes(item_instance: { item_revision: :item })
      served.map { |s| s.item_instance.item_revision }.uniq.sort_by(&:id)
    end
  end
end
