module Teacher
  # What the browser is told about one stored instance, with the stored order of its choices (no shuffle): the
  # presentation the student's own templates draw. Shared by "Tutte le domande" and the topic review.
  module StoredPresentation
    COLUMNS = %w[options elements left right].freeze

    module_function

    def call(instance, rev)
      served = ItemServed.new(item_instance: instance, skill_key: "", shown_order_json: stored_order(instance, rev).to_json)
      Diagnosis::ItemPresenter.new(served: served, number: 1, subject: rev.item.subject).as_json[:item]
    end

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
