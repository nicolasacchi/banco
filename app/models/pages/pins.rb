# Which lesson revisions pin a page revision (SPEC B4). A pin is the integer `revision` of a `page` block of a stored lesson/2.
module Pages
  module Pins
    module_function

    # Lesson revisions of the page's subject whose body pins +revision+.
    def lesson_revisions(revision)
      subject = revision.page.subject
      LessonRevision.joins(:lesson).where(lessons: { subject_id: subject.id }).select do |lr|
        lr.lesson2? && Embeds.of(lr.body).any? { |e| e[:key] == revision.page.key && e[:revision] == revision.id }
      end
    end

    def lesson_keys(revision) = lesson_revisions(revision).map { |lr| lr.lesson.key }.uniq.sort

    # Page revisions pinned by a lesson revision: [{embed:, revision: PageRevision or nil}].
    def of_lesson(lesson_revision)
      Embeds.of(lesson_revision.body).map do |e|
        { embed: e, revision: e[:revision].is_a?(Integer) ? PageRevision.find_by(id: e[:revision]) : nil }
      end
    end
  end
end
