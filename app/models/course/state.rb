module Course
  # Read-side facts about a subject's course map (A2.2, A4): its latest revision, whether a newer graph exists
  # than the one it was validated against (W-COURSE-GRAPH-STALE, computed at read time, never stored), and the
  # map the teacher released to the official student.
  module State
    module_function

    def latest(subject) = CourseRevision.where(subject: subject).order(:seq).last

    def latest_graph(subject) = SkillGraphRevision.where(subject: subject).order(:seq).last

    def graph_stale?(revision)
      newest = latest_graph(revision.subject)
      !newest.nil? && newest.seq > revision.skill_graph_revision.seq
    end

    # The stored warnings plus W-COURSE-GRAPH-STALE when it applies, as hashes.
    def warnings(revision)
      list = revision.warnings
      return list unless graph_stale?(revision)

      newest = latest_graph(revision.subject)
      list + [ Validation::Findings.new.add("W-COURSE-GRAPH-STALE", "/skill_graph_revision_id",
                                           "graph revision #{newest.id} is newer than #{revision.skill_graph_revision_id}, which this map was validated against: re-submit the map to validate it against revision #{newest.id}",
                                           rule: "stale").first.to_h.deep_stringify_keys ]
    end

    # The course revision the latest release_course decision of the subject opened, or nil when closed or never released.
    def released_revision_id(subject)
      decision = Decision.where(subject: subject, kind: "release_course").order(:id).last or return nil
      payload = JSON.parse(decision.payload_json)
      payload["open"] ? payload["course_revision_id"] : nil
    end
  end
end
