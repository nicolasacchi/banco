# Oggi, Materie and one Materia (A9.1, A9.2). Read-only pages.
class CourseController < ApplicationController
  include StudentCourse

  def today
    view = course_view
    @today = view.today
    @closed = view.subjects.empty?
    @resume = @today[:resume] && view.find_topic(@today[:resume])
    @suggestions = @today[:suggestions].filter_map do |s|
      found = view.find_topic(s.topic_key) or next
      { suggestion: s, subject_view: found[0], topic: found[1] }
    end
    @diagnosis_left = !@closed && diagnosis_left?
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

  # A subject of the diagnosis remains to do: only said when the diagnosis is open for this student.
  def diagnosis_left?
    return false unless diagnosis_open?

    Diagnosis::Availability.for(acting_student).any? { |row| !row.done }
  end
end
