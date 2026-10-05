module Validation
  # The Validation::Context of a subject, read from the database: the skills of its
  # latest graph, the skills of the approved graphs of other subjects, programme
  # lines and reference texts. Nothing is written.
  class CourseContext
    def self.for(subject)
      new(subject).context
    end

    def initialize(subject)
      @subject = subject
      @line_cache = {}
    end

    def context
      graph = latest_graph
      skills = graph ? JSON.parse(graph.body_json)["skills"].index_by { |s| s["key"] } : {}
      Validation::Context.new(
        subject: @subject.key,
        graph_present: !graph.nil?,
        skill: ->(key) { skills[key] || approved_skill(key) },
        approved_skill: ->(key) { approved_skill(key) },
        source_line: ->(source, number) { source_line(source, number) },
        source_section: ->(source, number) { source_section(source, number) },
        reference_body: ->(key) { ReferenceText.find_by(key: key)&.body }
      )
    end

    private

    def latest_graph = SkillGraphRevision.where(subject: @subject).order(:seq).last

    # A skill of the approved graph of its own subject, when that is not ours.
    def approved_skill(key)
      owner = key.to_s.split(".").first
      return nil if owner == @subject.key

      subject = Subject.find_by(key: owner) or return nil
      revision = SubjectStage.approved_graph(subject) or return nil
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
