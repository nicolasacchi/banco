# "Impostazioni": the student's theme and text size (B-11), reachable from the menu on every page.
# The choice is posted to /diagnosis/preferences (PreferencesController).
class SettingsController < ApplicationController
  include ActingStudent

  def show
    @preferences = Diagnosis::Preferences.for(acting_student)
  end
end
