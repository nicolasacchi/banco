# The student's Diagnosi screen: the list of subjects with their states, or, until
# the teacher has opened the diagnosis, one line and the warm-up (B-11).
class DiagnosisController < ApplicationController
  include ActingStudent

  def show
    @released = diagnosis_open?
    if @released
      @rows = Diagnosis::Availability.for(acting_student)
    else
      @warmup_done = Diagnosis::Warmup.complete?(acting_student)
    end
  end
end
