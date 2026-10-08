# The student's Diagnosi screen: the list of subjects with their states, or, until
# the teacher has opened the diagnosis, one line and the warm-up (B-11).
class DiagnosisController < ApplicationController
  include ActingStudent

  def show
    @released = diagnosis_open?
    # The link to Oggi only when this student has a visible topic: until the release the page is unchanged (A9.1).
    @course_link = Course::Catalog.for(acting_student).any? { |sv| sv.topics.any? }
    if @released
      @rows = Diagnosis::Availability.for(acting_student)
    else
      @warmup_done = Diagnosis::Warmup.complete?(acting_student)
    end
  end
end
