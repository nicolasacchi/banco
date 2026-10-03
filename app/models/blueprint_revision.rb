class BlueprintRevision < ApplicationRecord
  belongs_to :subject
  belongs_to :skill_graph_revision
  belongs_to :author_session, class_name: "AgentSession", optional: true

  # Ids of every item revision the blueprint pins: the entries and the descent pool.
  def pinned_item_revision_ids
    body = JSON.parse(body_json)
    (Array(body["entries"]).flat_map { |e| Array(e["items"]) } + Array(body["descent"]).flat_map { |d| Array(d["items"]) }).map(&:to_i).uniq
  end
end
