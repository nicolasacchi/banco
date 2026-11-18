# The privacy notice (D-357): the GDPR article 13 information for the student, the teacher and a guest. Texts in
# config/locales/privacy.*.yml; the operator's own values from the environment (Privacy::Notice).
class PrivacyController < ApplicationController
  include InfoPage

  def show
    @values = Privacy::Notice.values
  end
end
