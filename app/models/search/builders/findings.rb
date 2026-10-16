module Search
  module Builders
    # The review findings of the latest revision of each item: the quoted text, the problem and the fix (staff only).
    module Findings
      module_function

      def call
        ReviewFinding.where(item_revision_id: Latest.ids("item_revisions")).includes(item_revision: { item: :subject }).order(:id).map do |finding|
          revision = finding.item_revision
          item = revision.item
          Doc.build(kind: "finding", key: item.key, title: Text.plain(finding.problem_it).first(120), body: Text.join(finding.quote, Text.plain(finding.problem_it), Text.plain(finding.fix_it)),
                    subject: item.subject.key, revision_table: "item_revisions", revision_id: revision.id, status: finding.severity,
                    skill: Items.skill_of(JSON.parse(revision.body_json)), unique: finding.id, lang: ::Lessons::Lang.target(item.subject.key) || "it")
        end
      end
    end
  end
end
