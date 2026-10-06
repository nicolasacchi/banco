module Review
  # What a reviewer or a blind solver may see of an item revision, and the text a
  # review finding may quote (A-05): item.json, the instances shown (8 of a
  # generator item for the solver, every stored instance for the reviewer) and the programme lines the
  # item's skill cites. Never generator.mjs, verify.mjs, or another reviewer's work.
  class ItemText
    INSTANCES_OF_GENERATOR = 8

    attr_reader :revision

    # all: true lists every stored instance of a generator item (the reviewer, D-133);
    # the blind solver keeps the first INSTANCES_OF_GENERATOR.
    def initialize(revision, all: false)
      @revision = revision
      @all = all
    end

    def body = @body ||= JSON.parse(revision.body_json)

    def generated? = body["generator"].present?

    # Instance rows in the order the reviewer sees them; position + 1 is the number
    # findings and answers use ("instance": 1 is the first).
    def instances
      @instances ||= begin
        rows = revision.instances.order(:id)
        generated? && !@all ? rows.limit(INSTANCES_OF_GENERATOR).to_a : rows.to_a
      end
    end

    def instance_row(number) = number.is_a?(Integer) && number >= 1 ? instances[number - 1] : nil

    # {instance, display, answer, errors, solution} for the reviewer.
    def review_instances
      instances.each_with_index.map do |row, i|
        { instance: i + 1, display: with_passage(JSON.parse(row.display_json)), answer: JSON.parse(row.answer_json),
          errors: row.errors_json.present? ? JSON.parse(row.errors_json) : nil,
          solution: row.solution_json.present? ? JSON.parse(row.solution_json) : nil,
          accept: row.accept_json.present? ? JSON.parse(row.accept_json) : nil }.compact
      end
    end

    # {instance, display} for the blind solver: nothing that holds the key.
    def solver_instances
      instances.each_with_index.map { |row, i| { instance: i + 1, display: with_passage(JSON.parse(row.display_json)) } }
    end

    # The item's own passage (short answer, diagnosis item) belongs to what the
    # student reads; the stored display of older revisions does not hold it.
    def with_passage(display)
      body["passage_it"].present? && body["kind"] != "testlet" ? { "passage_it" => body["passage_it"] }.merge(display) : display
    end

    # Lines of the programme cited by the item's skill in its subject's graph.
    def programme_lines
      graph = SkillGraphRevision.where(subject: revision.item.subject).order(:seq).last or return []
      skills = body["kind"] == "testlet" ? Array(body["sub_items"]).map { |s| s["skill"] } : [ body["skill"] ]
      refs = JSON.parse(graph.body_json)["skills"].select { |s| skills.include?(s["key"]) }.flat_map { |s| s["refs"].to_a.map { |r| r.merge("skill" => s["key"]) } }
      refs.uniq { |r| [ r["source"], r["line"] ] }.filter_map do |ref|
        source = SyllabusSource.find_by(key: ref["source"]) or next
        line = SyllabusLine.find_by(syllabus_source: source, number: ref["line"]) or next
        next unless line.citable?

        { source: ref["source"], line: ref["line"], role: ref["role"], skill: ref["skill"], text: line.text.chomp }
      end
    end

    # Every string a quote may come from, for finding at +instance+ (nil: the item as
    # a whole, which may quote any shown instance too).
    def strings(instance: nil)
      rows = instance ? [ instance_row(instance) ].compact : instances
      # A finding about one instance quotes the item's own text or that instance, not
      # another instance written in item.json.
      pool = instance ? leaves(body.except("instances")) : [ revision.body_json ] + leaves(body)
      rows.each do |row|
        %w[display_json answer_json errors_json solution_json accept_json].each do |col|
          next if row[col].blank?

          pool.concat(leaves(JSON.parse(row[col])))
        end
      end
      pool.concat(programme_lines.map { |l| l[:text] })
      pool
    end

    def quote?(quote, instance: nil)
      return false if quote.to_s.empty?

      strings(instance: instance).any? { |s| s.include?(quote) }
    end

    private

    def leaves(node)
      case node
      when String then [ node ]
      when Hash then node.values.flat_map { |v| leaves(v) }
      when Array then node.flat_map { |v| leaves(v) }
      when Numeric then [ node.to_s ]
      else []
      end
    end
  end
end
