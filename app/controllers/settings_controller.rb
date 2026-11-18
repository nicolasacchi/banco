# "Impostazioni": the student's theme, text size and interface language (B-11, D-356), reachable from the menu on every page.
# The choice is posted to /diagnosis/preferences (PreferencesController).
class SettingsController < ApplicationController
  include ActingStudent

  def show
    @preferences = Diagnosis::Preferences.for(acting_student).merge(language: Diagnosis::Preferences.language(acting_student))
  end
end
