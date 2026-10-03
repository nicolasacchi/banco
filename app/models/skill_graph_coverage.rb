# `banco skill-graph coverage --subject KEY` (C-01): which lines of the subject's range
# in the previous year's programme no skill cites and no exclusion explains. The
# check is mechanical (a range, the citations, the exclusions), so "uncovered is
# empty" means something. The ranges are in config/banco/validation_rules.yml.
class SkillGraphCoverage
  def self.call(subject) = new(subject).to_h

  def initialize(subject)
    @subject = subject
  end

  def to_h
    graph = SkillGraphRevision.where(subject: @subject).order(:seq).last
    return nil unless graph

    body = JSON.parse(graph.body_json)
    source_key = Validation::Rules.get(:coverage, :prima_source)
    first, last = Validation::Rules.get(:coverage, :ranges).fetch(@subject.key)
    cited = body["skills"].flat_map { |s| Array(s["refs"]).select { |r| r["source"] == source_key }.map { |r| r["line"] } }.to_set
    excluded = Array(body["excluded"]).map { |e| e["line"] }.to_set
    lines = syllabus_lines(source_key, first, last)
    uncovered = lines.reject { |l| cited.include?(l.number) || excluded.include?(l.number) }
    {
      subject: @subject.key, graph_revision_id: graph.id, source: source_key, range: [ first, last ],
      lines: lines.size, cited: lines.count { |l| cited.include?(l.number) }, excluded: lines.count { |l| excluded.include?(l.number) && !cited.include?(l.number) },
      uncovered: uncovered.map { |l| { line: l.number, text: l.text } },
      skills: skills_with_items(body)
    }
  end

  private

  # Non-blank lines of the source's own content (the transcriber's lines are not
  # content and cannot be cited).
  def syllabus_lines(source_key, first, last)
    source = SyllabusSource.find_by(key: source_key)
    return [] unless source

    SyllabusLine.where(syllabus_source: source, number: first..last).where.not(origin: "transcript").order(:number).reject { |l| l.text.strip.empty? }
  end

  # Skills with and without an item whose latest revision passed validation.
  def skills_with_items(body)
    measured = Item.where(subject: @subject).filter_map do |item|
      rev = item.latest_revision
      next unless rev&.status == "passed"

      doc = JSON.parse(rev.body_json)
      doc["kind"] == "testlet" ? Array(doc["sub_items"]).map { |s| s["skill"] } : doc["skill"]
    end.flatten.to_set
    keys = body["skills"].map { |s| s["key"] }
    { total: keys.size, with_items: keys.count { |k| measured.include?(k) }, without_items: keys.reject { |k| measured.include?(k) } }
  end
end
