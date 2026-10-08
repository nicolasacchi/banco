module Course
  # What each student sees of the courses (A6.2). The topic is the lesson's key; a topic is visible when it
  # has a topic revision under these rules, and a subject with no visible topic is not listed.
  #
  #   official student: a subject whose latest release_course is closed is listed with released: false and
  #                     no topics (never released: not listed); otherwise the map of the latest release_course of the subject, only if it is open; for each
  #                     key the latest approve_topic whose topic revision's skills equal the map's
  #   trial student:    the latest map; the latest topic revision of each key if its skills equal the
  #                     map's (approved: false until the teacher approves that very revision)
  #   preview:          nothing (the slice has no teacher preview of the course)
  #
  #   Course::Catalog.for(student) # => [SubjectView]
  module Catalog
    SubjectView = Data.define(:subject, :mode, :course_revision, :released, :topics, :skills_without_topic)
    TopicView = Data.define(:key, :kind, :title_it, :term, :minutes, :skills, :after, :topic_revision, :lesson_revision, :approved)

    module_function

    def for(student)
      return [] unless student && student.kind == "student"

      decisions = Decision.where(kind: %w[release_course approve_topic]).order(:id).to_a
      Subject.order(:position).filter_map { |subject| subject_view(student, subject, decisions) }
    end

    def subject_view(student, subject, decisions)
      release = latest_release(subject, decisions)
      released = release.present? && release["open"] == true
      official = student.official?
      course = if official
        released ? CourseRevision.find_by(id: release["course_revision_id"]) : nil
      else
        CourseRevision.where(subject: subject).order(:seq).last
      end
      if official && release.present? && !released
        # Withdrawn after an open release: listed as closed, with no topics (S shows "Il corso non è ancora aperto.").
        return SubjectView.new(subject: subject, mode: :official, course_revision: nil, released: false, topics: [], skills_without_topic: [])
      end
      return nil unless course

      topics = course.body["topics"].filter_map { |entry| topic_view(entry, course, subject, decisions, official: official) }
      return nil if topics.empty?

      SubjectView.new(subject: subject, mode: official ? :official : :trial, course_revision: course, released: released, topics: topics,
                      skills_without_topic: skills_without_topic(course, topics))
    end

    def latest_release(subject, decisions)
      d = decisions.select { |x| x.kind == "release_course" && x.subject_id == subject.id }.last
      d && JSON.parse(d.payload_json)
    end

    def topic_view(entry, course, subject, decisions, official:)
      lesson = Lesson.find_by(subject: subject, key: entry["key"]) or return nil
      wanted = entry["skills"].sort
      approvals = decisions.select { |d| d.kind == "approve_topic" && d.subject_id == subject.id }.reverse
                           .map { |d| JSON.parse(d.payload_json) }.select { |p| p["topic"] == entry["key"] }
      revision = if official
        approvals.filter_map { |p| TopicRevision.find_by(id: p["topic_revision_id"]) }.find { |r| skills_of(r) == wanted }
      else
        latest = lesson.topic_revisions.max_by(&:seq)
        latest if latest && skills_of(latest) == wanted
      end
      return nil unless revision

      approved = official || approvals.any? { |p| p["topic_revision_id"] == revision.id }
      TopicView.new(key: entry["key"], kind: entry["kind"], title_it: entry["title_it"], term: entry["term"], minutes: entry["minutes"],
                    skills: entry["skills"], after: entry["after"], topic_revision: revision, lesson_revision: revision.lesson_revision, approved: approved)
    end

    # The skills a topic revision practices, sorted.
    def skills_of(topic_revision) = topic_revision.body["practice"].map { |p| p["skill"] }.sort

    # The graph and map skills of the subject that no visible topic holds (the pages name those that
    # the diagnosis found to recover or learn).
    def skills_without_topic(course, topics)
      graph = JSON.parse(course.skill_graph_revision.body_json)["skills"].map { |s| s["key"] }
      all = graph + course.body["skills"].map { |s| s["key"] }
      all.uniq - topics.flat_map(&:skills)
    end
  end
end
