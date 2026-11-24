module Items
  # One instance of an item revision as the student's page draws it, for the item shots (D-336). The instance is the n-th of the
  # revision's stored instances in the order of their ids (the number the solver's and the reviewer's openings use), shuffled with a
  # fixed seed (Diagnosis::Conductor.rekey, the serve-time shuffle of the student's sittings and practice) so that a picture is the same every
  # time and the solver can map what it sees to the stored ids with `shown_order`. What the browser is told is Diagnosis::ItemPresenter's
  # (Items::Part): never the key, the error values, the hints or the solution.
  module ShotPresentation
    FRAMES = { "practice_item" => "practice" }.freeze

    module_function

    def instances(revision) = revision.instances.order(:id)

    def instance(revision, number)
      return nil unless number.is_a?(Integer) && number >= 1

      instances(revision).offset(number - 1).first
    end

    # The seed of instance number n: stated in the shot's metadata.
    def seed(revision, number) = "item-shots|#{revision.id}|#{number}"

    # { number:, seed:, shown_order:, frame:, item:, hints: } for the host page; shown_order is {column => stored ids in the order shown}
    # (a testlet: per sub item), which the solver reads to map a position to a stored id.
    def call(revision, instance, number)
      body = JSON.parse(revision.body_json)
      shuffled = Diagnosis::Conductor.rekey(instance, body, seed(revision, number))
      served = ItemServed.new(item_instance: instance, skill_key: body["skill"].to_s, shown_order_json: shuffled.shown_order.to_json)
      item = Diagnosis::ItemPresenter.new(served: served, number: 1, subject: revision.item.subject).as_json[:item]
      { number: number, seed: seed(revision, number), shown_order: shuffled.shown_order, frame: FRAMES.fetch(body["kind"], "sitting"), item: item,
        hints: Practice::Instances.hints(instance).size }
    end

    # The shot of the same instance with the Italian translation open (D-402): the state of a picture drawn with `?tr=1`.
    TRANSLATION_STATE = "tr".freeze

    # Whether the revision has an Italian translation to picture (a bilingual item of english or spanish): a legacy item has no `-tr` shot.
    def translation?(revision) = JSON.parse(revision.body_json)["bilingual"] == true

    # What a shot says about its instance, without the page's data: its number, the seed and the shown order, and, for the picture drawn with the
    # translation open, `state: "tr"` (the pictures as drawn have no state).
    def meta(presentation, state: nil)
      { "instance" => presentation[:number], "seed" => presentation[:seed], "shown_order" => presentation[:shown_order] }.tap { |meta| meta["state"] = state if state }
    end
  end
end
