module Validation
  # The Validation::Context of a subject, read from the database: the skills of its
  # latest graph, the skills of the approved graphs of other subjects, programme
  # lines and reference texts. Nothing is written.
  class CourseContext
    # course: false leaves the subject's course map out of skill (the map is validated against the graph alone).
    def self.for(subject, course: true)
      new(subject, course: course).context
    end

    def initialize(subject, course: true)
      @subject = subject
      @course = course
      @line_cache = {}
    end

    def context
      graph = latest_graph
      skills = graph ? JSON.parse(graph.body_json)["skills"].index_by { |s| s["key"] } : {}
      Validation::Context.new(
        subject: @subject.key,
        graph_present: !graph.nil?,
        skill: ->(key) { skills[key] || (@course && course_skills[key]) || approved_skill(key) },
        graph_skill: ->(key) { skills[key] || approved_skill(key) },
        approved_skill: ->(key) { approved_skill(key) },
        draft_skill: ->(key) { draft_skill(key) },
        source_line: ->(source, number) { source_line(source, number) },
        source_section: ->(source, number) { source_section(source, number) },
        reference_body: ->(key) { ReferenceText.find_by(key: key)&.body },
        topic: ->(key) { course_topics.include?(key) }
      )
    end

    private

    # The topic keys of the subject's latest course map (lesson/2 links, A5).
    def course_topics
      @course_topics ||= Array(Course::State.latest(@subject)&.body&.fetch("topics", nil)).map { |t| t["key"] }
    end

    def latest_graph = SkillGraphRevision.where(subject: @subject).order(:seq).last

    # The seconda skills of the subject's latest course map (Phase 1b): same shape as graph skills.
    def course_skills
      @course_skills ||= begin
        revision = CourseRevision.where(subject: @subject).order(:seq).last
        revision ? JSON.parse(revision.body_json)["skills"].index_by { |s| s["key"] } : {}
      end
    end

    # A skill of the approved graph of its own subject, when that is not ours.
    def approved_skill(key)
      owner = key.to_s.split(".").first
      return nil if owner == @subject.key

      subject = Subject.find_by(key: owner) or return nil
      revision = SubjectStage.approved_graph(subject) or return nil
      JSON.parse(revision.body_json)["skills"].find { |s| s["key"] == key }
    end

    # A skill of the latest graph of its own subject, approved or not (a guest
    # entry in a draft; the approval gate still wants the approved graph).
    def draft_skill(key)
      owner = key.to_s.split(".").first
      return nil if owner == @subject.key

      subject = Subject.find_by(key: owner) or return nil
      revision = SkillGraphRevision.where(subject: subject).order(:seq).last or return nil
      JSON.parse(revision.body_json)["skills"].find { |s| s["key"] == key }
    end

    def source_line(source, number)
      @line_cache[[ source, number ]] ||= begin
        src = SyllabusSource.find_by(key: source)
        line = src && SyllabusLine.find_by(syllabus_source: src, number: number)
        line ? { text: line.text, origin: line.origin, marker: line.marker, block_marker: block_markers(src)[number]&.fetch(:marker) } : false
      end || nil
    end

    def source_section(source, number)
      @sections ||= {}
      @sections[source] ||= begin
        src = SyllabusSource.find_by(key: source)
        src ? Syllabus::Sections.call(SyllabusLine.where(syllabus_source: src).order(:number).to_a) : {}
      end
      @sections[source][number]
    end

    # Inherited star markers of a source, computed once per validation.
    def block_markers(src)
      @block_markers ||= {}
      @block_markers[src.id] ||= Syllabus::BlockMarker.call(SyllabusLine.where(syllabus_source: src).order(:number).to_a)
    end
  end
end
