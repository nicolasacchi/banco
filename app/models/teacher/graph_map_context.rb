module Teacher
  # What the map of a graph needs besides the graph itself (D-221): the map (cached by revision),
  # the questions the current test pins on each skill, the skills the test starts from, and the
  # second year's programme lines the skills cite. Read-only.
  class GraphMapContext
    PinnedItem = Data.define(:revision_id, :key, :component, :seq)

    attr_reader :review, :subject

    # blueprint: the test whose pins are shown (the latest one by default; the report passes the run's).
    def initialize(review, blueprint: :latest)
      @review = review
      @subject = review.subject
      @blueprint = blueprint == :latest ? BlueprintRevision.where(subject: subject).order(:seq).last : blueprint
    end

    def map
      @map ||= GraphMap.call(skills: review.skills, stub_labels: stub_labels, seconda: seconda_lines, revision_id: review.revision.id)
    end

    def items(key) = pinned.fetch(key, [])
    def pinned_count(key) = items(key).size
    def entry?(key) = entries.include?(key)
    def in_test?(key) = rows.key?(key)
    def seconda_lines = @seconda_lines ||= build_seconda
    def seconda_for(key) = review.skills.find { |s| s.key == key }&.refs.to_a.select { |r| seconda_ref?(r) }
    def refs = @refs ||= Teacher::Refs.new

    def seconda_ref?(ref) = ref.role == "needed_by" && ref.source.to_s.start_with?("seconda")

    private

    def stub_labels
      review.skills.flat_map { |s| s.deferred.select { |d| d[:where] == :prerequisite }.map { |d| d[:skill] } }.uniq.to_h { |k| [ k, refs.skill_label(k) ] }
    end

    def build_seconda
      grouped = {}
      review.skills.each do |skill|
        skill.refs.select { |r| seconda_ref?(r) }.each do |r|
          id = "seconda:#{r.source}:#{r.line}"
          row = grouped[id] ||= { id: id, source: r.source, line: r.line, text: r.text.to_s, section: r.section.to_s, skills: [] }
          row[:skills] << skill.key unless row[:skills].include?(skill.key)
        end
      end
      grouped.values.sort_by { |l| [ l[:source], l[:line] ] }
    end

    def rows
      @rows ||= @blueprint ? blueprint_rows.to_h { |r| [ r[:skill], r ] } : {}
    end

    def blueprint_rows
      body = JSON.parse(@blueprint.body_json)
      (Array(body["entries"]).map { |e| e.merge("role" => "entry") } + Array(body["descent"]).map { |e| e.merge("role" => "descent") })
        .map { |e| { skill: e["skill"], role: e["role"], ids: Array(e["items"]).map(&:to_i) } }
    end

    def entries = @entries ||= rows.values.select { |r| r[:role] == "entry" }.map { |r| r[:skill] }.to_set

    def pinned
      @pinned ||= begin
        ids = rows.values.flat_map { |r| r[:ids] }.uniq
        revisions = ItemRevision.where(id: ids).includes(:item).index_by(&:id)
        rows.transform_values do |r|
          r[:ids].filter_map { |id| revisions[id] }.map do |rev|
            body = JSON.parse(rev.body_json)
            PinnedItem.new(rev.id, rev.item.key, body["kind"] == "diagnosis_item" ? body["component"] : body["kind"], rev.seq)
          end
        end
      end
    end
  end
end
