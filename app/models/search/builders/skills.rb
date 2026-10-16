module Search
  module Builders
    # The skills of the latest graph of each subject (staff only).
    module Skills
      module_function

      def call
        approved = Decision.where(kind: "approve_skill_graph").pluck(:payload_json).filter_map { |json| JSON.parse(json)["revision_id"] }.to_set
        Latest.ids("skill_graph_revisions").flat_map do |id|
          revision = SkillGraphRevision.includes(:subject).find(id)
          status = approved.include?(revision.id) ? "approved" : "draft"
          Array(JSON.parse(revision.body_json)["skills"]).map do |skill|
            Doc.build(kind: "skill", key: skill["key"], title: skill["label_it"], subject: revision.subject.key, revision_table: "skill_graph_revisions",
                      revision_id: revision.id, status: status, skill: skill["key"], lang: ::Lessons::Lang.target(revision.subject.key) || "it",
                      body: Text.join(Text.plain(skill["note_it"]), Text.plain(skill["scope_reason_it"]),
                                      Array(skill["errors"]).map { |e| Text.plain(e["description_it"]) }))
          end
        end
      end
    end
  end
end
