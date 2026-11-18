# The privacy notice (D-357): the GDPR article 13 information for the student, the teacher and a guest. Texts in
# config/locales/privacy.*.yml; the operator's own values from the environment (Privacy::Notice).
# «Scarica i miei dati» (D-360, art. 15 and 20): the student's own zip. Only a student (official or trial), only his own rows; the
# teacher, a guest and the preview (no route) are refused, and no parameter names a student.
class PrivacyController < ApplicationController
  include InfoPage
  include StudentDataDownload

  before_action :require_student!, only: :data

  def show
    @values = Privacy::Notice.values
  end

  def data
    send_student_data(acting_student, by: "student")
  end
end
