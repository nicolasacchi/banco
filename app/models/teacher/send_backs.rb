module Teacher
  # "Rimanda": the teacher sends an item revision back to the content agent with a code
  # for the reason and a comment (decision kind send_back_item). The agent reads the
  # comments with `banco work open` and `banco work status`; a sent-back revision is not
  # approvable, so a new revision has to replace it.
  module SendBacks
    CODES = %w[wrong_key ambiguous_text wrong_error_code off_programme too_hard too_easy unclear_wording other].freeze

    module_function

    # {revision id => [payload, ...]} for the given revisions (all when nil), oldest first.
    def by_revision(revision_ids = nil)
      rows = Decision.where(kind: "send_back_item").order(:id).to_a.map { |d| JSON.parse(d.payload_json).merge("at" => d.created_at.utc.iso8601) }
      rows = rows.select { |p| revision_ids.include?(p["item_revision_id"]) } if revision_ids
      rows.group_by { |p| p["item_revision_id"] }
    end

    def sent_back?(revision) = by_revision([ revision.id ]).key?(revision.id)

    # What the agent sees for one item: every comment on any of its revisions.
    def for_item(item)
      revisions = item.revisions.to_h { |r| [ r.id, r.seq ] }
      by_revision(revisions.keys).flat_map do |id, comments|
        comments.map { |p| { revision_id: id, seq: revisions[id], reason_code: p["reason_code"], comment_it: p["comment_it"], at: p["at"] } }
      end.sort_by { |c| [ c[:at], c[:revision_id] ] }
    end
  end
end
