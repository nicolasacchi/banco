# Oggi, Materie and one Materia (A9.1, A9.2). Read-only pages.
class CourseController < ApplicationController
  include StudentCourse

  def today
    view = course_view
    @today = view.today
    @course_open = view.subjects.any?
    @resume = @today[:resume] && view.find_topic(@today[:resume])
    # A lesson/2 read up to a card: "Riprendi" opens that card (A10). The page's own events, not a skill state.
    @resume_card = @resume && Lessons::Progress.resume_card(acting_student, @resume[1].topic_revision, @resume[1].skills)
    @suggestions = @today[:suggestions].filter_map do |s|
      found = view.find_topic(s.topic_key) or next
      { suggestion: s, subject_view: found[0], topic: found[1] }
    end
    load_diagnosis_block
    @nothing = !@course_open && @diagnosis.nil?
  end

  def subjects
    @subjects = course_view.subjects
    @closed = @subjects.empty?
  end

  def subject
    @subject_view = course_view.subject(params[:key]) or return head(:not_found)

    @without_topic = course_view.skills_without_topic(@subject_view)
  end

  private

  # The "Test d'ingresso" block of Oggi (D-240): the rows of Diagnosis::Availability with the one clear next step,
  # when the diagnosis is open for this student; before that the optional warm-up and a line that the tests open
  # when the teacher opens them (D-261). The warm-up is a secondary link, never a gate. No rule of its own: the
  # next subject is the one the diagnosis screen suggests.
  def load_diagnosis_block
    warmup_done = Diagnosis::Warmup.complete?(acting_student)
    if diagnosis_open?
      rows = Diagnosis::Availability.for(acting_student)
      @diagnosis = { open: true, warmup_done: warmup_done, rows: rows, all_done: rows.any? && rows.all?(&:done),
                     next_row: rows.find(&:suggested) || rows.find(&:startable) }
    else
      @diagnosis = { open: false, warmup_done: warmup_done, rows: [], all_done: false, next_row: nil }
    end
  end
end
