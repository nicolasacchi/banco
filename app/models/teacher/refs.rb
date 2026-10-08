module Teacher
  # What the teacher's pages say about a key (operator request 2026-10-07, D-218): the Italian
  # name of a skill or an item and the facts of its card, read from the current graph, the
  # latest test and the item's latest revision. One instance serves one request: it
  # remembers what it has read. Read-only; the student never sees keys, so none of this
  # reaches the student's pages.
  class Refs
    COMPONENTS = %w[number fraction expression choice ordering matching normalized_text short_answer testlet].freeze
    KEY = /\A[a-z0-9][a-z0-9._-]*\z/

    Line = Data.define(:source, :line, :text)
    Name = Data.define(:key, :label)
    SkillCard = Data.define(:kind, :key, :name, :subject, :label_it, :layer, :scope, :note_it, :test_kind, :test_kind_reason_it, :lines, :inferred,
                            :needed_by, :prerequisites, :pinned, :in_test, :has_block, :has_report)
    ItemCard = Data.define(:kind, :key, :name, :subject, :revision, :skill, :skill_name, :component, :seq, :pinned, :instances, :status, :findings,
                           :open_findings, :blind, :review_fails, :corrections, :skill_in_test, :item_kind)

    # The record or the key as a card, nil when nothing has that key.
    def resolve(target)
      case target
      when Item then item_card(target)
      when ItemRevision then item_card(target.item)
      else
        key = target.to_s
        return nil unless key.match?(KEY)

        key.include?(".") ? skill(key) : item(key)
      end
    end

    def skill(key)
      @skills ||= {}
      @skills.fetch(key) { @skills[key] = build_skill(key) }
    end

    def item(key)
      @items ||= {}
      @items.fetch(key) { @items[key] = (record = Item.find_by(key: key)) && item_card(record) }
    end

    # The Italian name of a skill key, the key itself when the graph does not know it.
    def skill_label(key) = skill_row(key)&.dig("label_it") || key

    def self.component_name(component) = I18n.t("teacher.refs.component.#{component}", default: component.to_s)

    private

    def subject_of(key) = (@subjects ||= {}).fetch(key) { @subjects[key] = Subject.find_by(key: key.to_s.split(".").first) }

    # The current graph of a subject: its latest revision (what the teacher's graph page shows).
    def graph(subject)
      @graphs ||= {}
      @graphs.fetch(subject.id) do
        revision = SkillGraphRevision.where(subject: subject).order(:seq).last
        @graphs[subject.id] = revision && JSON.parse(revision.body_json)
      end
    end

    def blueprint(subject)
      @blueprints ||= {}
      @blueprints.fetch(subject.id) do
        revision = BlueprintRevision.where(subject: subject).order(:seq).last
        @blueprints[subject.id] = revision && [ revision, JSON.parse(revision.body_json) ]
      end
    end

    def skill_row(key)
      subject = subject_of(key) or return nil
      Array(graph(subject)&.dig("skills")).find { |s| s["key"] == key }
    end

    def names(subject, keys)
      keys.map { |k| Name.new(k, Array(graph(subject)&.dig("skills")).find { |s| s["key"] == k }&.dig("label_it") || k) }
    end

    def build_skill(key)
      return nil unless key.match?(KEY) && key.include?(".")

      subject = subject_of(key) or return nil
      row = skill_row(key) or return nil
      body = graph(subject)
      lines = Array(row["refs"]).select { |r| r["role"] == "taught_in" }.map { |r| Line.new(r["source"], r["line"], line_text(r["source"], r["line"])) }
      needed_by = body["skills"].select { |s| Array(s["prerequisites"]).include?(key) }.map { |s| s["key"] }
      entry = test_entry(subject, key)
      override = blueprint(subject) && Array(blueprint(subject)[1]["kind_overrides"]).find { |o| o["skill"] == key }
      pinned = entry ? Array(entry["items"]).size : 0
      SkillCard.new(:skill, key, row["label_it"], subject, row["label_it"], row["layer"], row["scope"], row["scope_reason_it"],
                    override && override["kind"], override && override["reason_it"], lines, lines.empty?,
                    names(subject, needed_by), names(subject, Array(row["prerequisites"])), pinned, !entry.nil?, pinned.positive?, report?(subject))
    end

    def test_entry(subject, key)
      body = blueprint(subject)&.last or return nil
      (Array(body["entries"]) + Array(body["descent"])).find { |e| e["skill"] == key }
    end

    # The report page has a row for every skill once a student's run exists.
    def report?(subject)
      @reports ||= {}
      @reports.fetch(subject.id) do
        @reports[subject.id] = DiagnosisRun.joins(:student).where(subject: subject, students: { kind: "student", key: Student::OFFICIAL_KEY }).exists?
      end
    end

    def line_text(source, number)
      @texts ||= {}
      @texts.fetch([ source, number ]) do
        @texts[[ source, number ]] = SyllabusLine.joins(:syllabus_source).where(syllabus_sources: { key: source }, number: number).pick(:text)&.strip
      end
    end

    def item_card(record)
      @item_cards ||= {}
      @item_cards.fetch(record.id) { @item_cards[record.id] = build_item(record) }
    end

    def build_item(record)
      revision = ItemRevision.where(item: record).order(:seq).last or return nil
      body = JSON.parse(revision.body_json)
      skill_key = body["skill"].to_s
      component = %w[diagnosis_item practice_item].include?(body["kind"]) ? body["component"] : body["kind"]
      subject = record.subject
      title = body["title_it"].presence
      skill_name = skill_label(skill_key)
      name = title || I18n.t("teacher.refs.item_name", skill: skill_name, component: self.class.component_name(component))
      pinned_ids = blueprint(subject) ? blueprint(subject)[0].pinned_item_revision_ids : []
      findings = revision.findings.to_a
      open = ReviewFinding.must_be_disposed.where(item_revision_id: revision.id).count { |f| !dispositions.key?(f.id) }
      blind = revision.blind_solves.max_by(&:id)
      review = revision.reviews.max_by(&:id)
      ItemCard.new(:item, record.key, name, subject, revision, skill_key, skill_name, component, revision.seq, pinned_ids.include?(revision.id),
                   revision.instances.count, revision.status, findings.size, open, blind && blind_outcome(blind),
                   review && JSON.parse(review.checklist_json).count { |c| c["result"] == "fail" }, corrections_count(record.key),
                   !skill_key.empty? && !test_entry(subject, skill_key).nil?, record.kind)
    end

    def dispositions = @dispositions ||= ReviewFinding.dispositions

    def blind_outcome(blind)
      results = JSON.parse(blind.results_json)
      { ok: results.count { |r| %w[correct short_answer].include?(r["verdict"]) }, total: results.size }
    end

    def corrections_count(key)
      @corrections ||= Teacher::Corrections.call
      (@corrections.short_answers.map(&:item_key) + @corrections.verdicts.map(&:item_key)).count(key)
    end
  end
end
