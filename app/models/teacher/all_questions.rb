module Teacher
  # Every question of one entry test on one page (operator request 2026-10-07): the pinned
  # items of the latest blueprint revision, entries first and then the descent pool, grouped
  # by skill, each with ALL its stored instances. Read-only: the browser draws each instance
  # with the student's own templates, from the same presentation the student's page gets
  # (Diagnosis::ItemPresenter, in the stored order, not shuffled). What the teacher alone may
  # see (the key, the typical errors, the solution, the rubric) is rendered inside a hidden
  # block that "Mostra risposte" opens in the browser; the page exists only for the teacher.
  class AllQuestions
    Group = Data.define(:row, :scope, :items)
    Entry = Data.define(:revision, :item, :body, :component, :instances, :rubric)
    Inst = Data.define(:id, :number, :presentation, :view)

    attr_reader :review

    def initialize(review)
      @review = review
    end

    delegate :subject, :blueprint, :approved_latest?, to: :review

    def pinned_ids = blueprint.pinned_item_revision_ids

    def groups
      @groups ||= begin
        revisions = ItemRevision.where(id: pinned_ids).includes(:item, :instances).index_by(&:id)
        scopes = JSON.parse(review.graph.body_json)["skills"].to_h { |s| [ s["key"], s["scope"] ] }
        review.skill_rows.filter_map do |row|
          entries = row.item_ids.filter_map { |id| revisions[id] }.map { |rev| entry(rev) }
          Group.new(row, scopes[row.skill], entries) if entries.any?
        end
      end
    end

    def item_count = groups.sum { |g| g.items.size }
    def instance_count = groups.sum { |g| g.items.sum { |i| i.instances.size } }

    private

    def entry(rev)
      body = JSON.parse(rev.body_json)
      instances = rev.instances.sort_by(&:id).each_with_index.map do |inst, i|
        Inst.new(inst.id, i + 1, presentation(inst, rev), InstanceView.new(inst, body, i + 1))
      end
      component = body["kind"] == "testlet" ? "testlet" : (body["kind"] == "short_answer" ? "short_answer" : body["component"])
      Entry.new(rev, rev.item, body, component, instances, body["rubric"])
    end

    # What the browser is told, with the stored order of the choices (no shuffle).
    def presentation(instance, rev)
      served = ItemServed.new(item_instance: instance, skill_key: "", shown_order_json: stored_order(instance, rev).to_json)
      Diagnosis::ItemPresenter.new(served: served, number: 1, subject: rev.item.subject).as_json[:item]
    end

    COLUMNS = %w[options elements left right].freeze

    def stored_order(instance, rev)
      body = JSON.parse(rev.body_json)
      display = JSON.parse(instance.display_json)
      if body["kind"] == "testlet"
        Array(display["sub_items"]).to_h { |s| [ s["id"], order_of(s["display"] || {}) ] }
      else
        order_of(display)
      end
    end

    def order_of(display)
      COLUMNS.filter_map { |k| [ k, display[k].map { |e| e["id"] } ] if display[k].is_a?(Array) }.to_h
    end
  end
end
