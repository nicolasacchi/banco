# «Novità» (D-375): the small dot on the student's menu entry when something is newer than his last visit to the page.
module ChangelogHelper
  # True when the entries, the topics revised or his own comments' follow-ups include something after the last `changelog_viewed` (before the first
  # visit: after his account began). Never in the teacher's preview: it has no visits and no dot. Memoised for the request; the page itself
  # records its visit before the menu is drawn, so it never shows the dot on its own page.
  def changelog_new?
    return @_changelog_new unless @_changelog_new.nil?

    student = respond_to?(:acting_student) && !preview? ? acting_student : nil
    @_changelog_new = !student.nil? && begin
      view = respond_to?(:course_view) ? course_view : Course::StudentView.new(student)
      Changelog::Feed.student(student, view, recent: true).newer_than?(Changelog::Visits.last_seen(student))
    end
  end

  # The student's pages that the teacher's preview also has.
  PREVIEW_PAGES = %r{\A/(today|subjects|schemas|settings|search|novita)\z}

  # Where the teacher goes from an entry's link: a teacher page as it is, the privacy and account pages (for everyone), a page of the student's
  # through the preview (a guest and a view link have none), nothing for a page that has no preview (the student's comments).
  def teacher_changelog_link(link)
    return nil if link.blank?
    return link if link.start_with?("/teacher") || %w[/privacy /account].include?(link)
    return nil if reader_only? || view_session?

    "#{ActingStudent::PREVIEW_ROOT}#{link}" if link.match?(PREVIEW_PAGES)
  end
end
