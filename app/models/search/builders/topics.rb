module Search
  module Builders
    # The topics of the live topic revisions (title and intro as the student's topic page shows them, with the labels of the
    # skills it practises), and one course document per subject for the staff.
    module Topics
      module_function

      def call
        approved = Live.approved_topic_revision_ids
        topics = Live.topic_revisions.filter_map { |revision| topic_doc(revision, approved.include?(revision.id) ? "approved" : "draft") }
        topics + courses
      end

      def topic_doc(revision, status)
        lesson = revision.lesson
        course = revision.course_revision.body
        entry = Array(course["topics"]).find { |t| t["key"] == lesson.key } or return nil
        labels = skill_labels(revision.course_revision)
        skills = Array(entry["skills"]).map { |s| labels[s] || s }
        Doc.build(kind: "topic", key: lesson.key, title: entry["title_it"], body: Text.join(Text.plain(revision.body["intro_it"]), skills),
                  subject: lesson.subject.key, revision_table: "topic_revisions", revision_id: revision.id, status: status, topic_key: lesson.key,
                  lang: ::Lessons::Lang.target(lesson.subject.key) || "it")
      end

      def skill_labels(course_revision)
        graph = JSON.parse(course_revision.skill_graph_revision.body_json)["skills"]
        (graph + course_revision.body["skills"].to_a).to_h { |s| [ s["key"], s["label_it"] ] }
      end

      def courses
        Latest.ids("course_revisions").filter_map do |id|
          revision = CourseRevision.includes(:subject).find(id)
          labels = skill_labels(revision)
          titles = Array(revision.body["topics"]).map { |t| t["title_it"] }
          Doc.build(kind: "course", key: "course.#{revision.subject.key}", title: I18n.t("search.course_title", subject: revision.subject.name_it),
                    body: Text.join(titles, labels.values), subject: revision.subject.key, revision_table: "course_revisions", revision_id: revision.id,
                    status: Course::State.released_revision_id(revision.subject) == revision.id ? "released" : "draft")
        end
      end
    end
  end
end
