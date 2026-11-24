# «Novità» (D-375), the student's side: what is new for him, newest first. Three sources, none of them a model: the entries that git holds
# (config/banco/changelog.yml), the topics the teacher approved again (read from the ledger, only those his course shows, never the teacher's
# reason) and «Le tue segnalazioni» (his own comments on a topic that was revised after them). Opening the page records one app event
# `changelog_viewed` (the dot on the menu entry compares with it); the teacher's preview shows the page and records nothing.
# Off for a student whose key is in BANCO_CHANGELOG_OFF (D-401): the page goes to Oggi and records nothing; the preview follows the official student.
class ChangelogController < ApplicationController
  include StudentCourse

  before_action :to_today, if: :changelog_off?

  def show
    @feed = Changelog::Feed.student(acting_student, course_view, recent: true)
    return if preview?

    # What counts as new is what came after the last visit; this visit is recorded after it was read.
    @since = Changelog::Visits.last_seen(acting_student)
    Changelog::Visits.record!(acting_student, new_count: @feed.new_count(@since))
  end

  private

  def to_today = redirect_to("#{student_root}/today")
end
