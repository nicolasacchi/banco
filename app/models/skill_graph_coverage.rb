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
    refs = body["skills"].flat_map { |s| Array(s["refs"]).select { |r| r["source"] == source_key } }
    cited = refs.map { |r| r["line"] }.to_set
    # An exclusion with a fragment leaves the rest of its line to the skills; one
    # without it covers the whole line.
    exclusions = Array(body["excluded"])
    excluded = exclusions.reject { |e| e["fragment"] }.map { |e| e["line"] }.to_set
    fragment_exclusions = exclusions.select { |e| e["fragment"] }.group_by { |e| e["line"] }
    lines = syllabus_lines(source_key, first, last)
    partial = partial_lines(lines, refs, fragment_exclusions, excluded)
    uncovered = lines.select do |l|
      if cited.include?(l.number) || excluded.include?(l.number)
        false
      elsif fragment_exclusions[l.number]
        partial.key?(l.number) # some of its text is still unaccounted for
      else
        true
      end
    end
    {
      subject: @subject.key, graph_revision_id: graph.id, source: source_key, range: [ first, last ],
      lines: lines.size, cited: lines.count { |l| cited.include?(l.number) }, excluded: lines.count { |l| (excluded.include?(l.number) || (fragment_exclusions[l.number] && !partial.key?(l.number))) && !cited.include?(l.number) },
      uncovered: uncovered.map { |l| { line: l.number, text: l.text } },
      partial: partial.values,
      skills: skills_with_items(body),
      item_errors_not_in_graph: item_errors_not_in_graph(body),
      testlets_multi_skill: testlets_multi_skill
    }
  end

  private

  # Lines that are only in part accounted for: some of the text is neither inside a
  # cited fragment nor inside an excluded one. Informational for a cited line (a
  # fragment is allowed to be short); for a line that is only fragment-excluded it
  # keeps the line uncovered. Whole-line exclusions are not listed.
  # { number => { line:, text:, cited: [fragments], excluded: [{fragment, reason_it}], unaccounted: [segments] } }
  def partial_lines(lines, refs, fragment_exclusions, whole)
    by_line = refs.group_by { |r| r["line"] }
    lines.each_with_object({}) do |l, out|
      next if whole.include?(l.number)

      cites = by_line.fetch(l.number, []).map { |r| r["fragment"] }.uniq
      excl = fragment_exclusions.fetch(l.number, [])
      next if cites.empty? && excl.empty?

      rest = unaccounted(l.text, cites + excl.map { |e| e["fragment"] })
      next if rest.empty?

      out[l.number] = { line: l.number, text: l.text, cited: cites, excluded: excl.map { |e| { fragment: e["fragment"], reason_it: e["reason_it"] } }, unaccounted: rest }
    end
  end

  # The pieces of +text+ left once every occurrence of each fragment is taken out,
  # without the pieces that hold no letter or digit (markers, bullets, punctuation).
  def unaccounted(text, fragments)
    covered = Array.new(text.length, false)
    fragments.each do |f|
      next if f.to_s.empty?

      from = 0
      while (at = text.index(f, from))
        (at...(at + f.length)).each { |i| covered[i] = true }
        from = at + 1
      end
    end
    segments = []
    current = +""
    text.each_char.with_index do |ch, i|
      if covered[i]
        segments << current
        current = +""
      else
        current << ch
      end
    end
    segments << current
    segments.map(&:strip).select { |seg| seg.match?(/[[:alnum:]]/) }
  end

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
      doc["kind"] == "testlet" ? Array(doc["sub_items"]).first&.dig("skill") : doc["skill"] # a testlet counts for its first skill (D-098)
    end.compact.to_set
    keys = body["skills"].map { |s| s["key"] }
    { total: keys.size, with_items: keys.count { |k| measured.include?(k) }, without_items: keys.reject { |k| measured.include?(k) } }
  end

  # Error codes that the latest passed revisions of the subject's items declare and the
  # latest graph does not list for the skill (W-ERROR-NOT-IN-GRAPH, D-137). The engine
  # reads errors from the graph alone, so such a wrong answer is unclassified and the
  # descent adds every direct prerequisite. Item validation only warns when a graph
  # existed at that time, so this list is the check after the fact.
  def item_errors_not_in_graph(body)
    known = body["skills"].to_h { |s| [ s["key"], Array(s["errors"]).map { |e| e["code"] }.to_set ] }
    Item.where(subject: @subject).order(:key).flat_map do |item|
      rev = item.latest_revision
      next [] unless rev&.status == "passed"

      doc = JSON.parse(rev.body_json)
      # A testlet is charged to its first sub item's skill only (D-098), so all its
      # codes are checked there (D-151).
      testlet = doc["kind"] == "testlet"
      bodies = testlet ? Array(doc["sub_items"]) : [ doc ]
      skill = testlet ? bodies.first&.dig("skill") : doc["skill"]
      bodies.flat_map do |b|
        codes = Array(b["error_catalogue"]).map { |e| e["code"] }.uniq.reject { |c| known[skill]&.include?(c) }
        codes.map { |c| { item: item.key, item_revision_id: rev.id, skill: skill, code: c } }
      end.uniq
    end
  end

  # Stored testlets (passed before E-TESTLET-SKILLS, D-098) whose sub items are on
  # several skills: the engine charges the first only, and a text-only resubmission
  # would fail E-TESTLET-SKILLS (D-151).
  def testlets_multi_skill
    Item.where(subject: @subject).order(:key).filter_map do |item|
      rev = item.latest_revision
      next unless rev&.status == "passed"

      doc = JSON.parse(rev.body_json)
      next unless doc["kind"] == "testlet"

      skills = Array(doc["sub_items"]).map { |s| s["skill"] }.uniq
      next if skills.size < 2

      { item: item.key, item_revision_id: rev.id, skills: skills, charged_to: skills.first }
    end
  end
end
