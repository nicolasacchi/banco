module Teacher
  # One pinned item revision as the teacher reads it (C-04, D-220): the sample instances, the error
  # catalogue, the gate, the review, the blind solve and the findings with their dispositions. Shared by the
  # entry test's skill screens (TestReview) and the topic review (TopicReview). Read-only.
  module ItemCard
    SAMPLES = 4

    Card = Data.define(:revision, :item, :body, :samples, :catalogue, :sources, :gate, :review, :blind, :findings, :send_backs, :superseded)
    # opinion: the third reviewer's FindingOpinion (D-222). closure: for a minor finding without a decision,
    # what the third reviewer's agreeing opinions make of it, :closed or :to_fix, else nil (a derived state, no decision row).
    Finding = Data.define(:finding, :disposition, :new_revision_expected, :evidence, :response, :opinion, :closure)
    # What the teacher needs to judge a blind-solve finding (D-220): the key of the instance as the
    # student would type it, the other answers accepted, and what the solver wrote.
    Evidence = Data.define(:key, :accepted, :solver_answer, :dont_know)

    module_function

    # Revisions loaded with what the card reads (one query each, not one per card).
    def load(ids) = ItemRevision.where(id: ids).includes(:item, :instances, { findings: :blind_solve }, :reviews, :blind_solves, :validations).index_by(&:id)

    def build(rev, dispositions, back)
      item_body = JSON.parse(rev.body_json)
      samples = rev.instances.sort_by(&:id).first(SAMPLES).each_with_index.map { |inst, i| InstanceView.new(inst, item_body, i + 1) }
      review = rev.reviews.max_by(&:id)
      blind = rev.blind_solves.max_by(&:id)
      later = rev.item.revisions.map(&:seq).max.to_i > rev.seq
      sorted = rev.findings.sort_by(&:id)
      responses = FindingResponse.latest_for(sorted.map(&:id))
      opinions = FindingAssessment.opinions_for(sorted.map(&:id))
      findings = sorted.map do |f|
        disposition = dispositions[f.id]
        closure = f.severity == "minor" && disposition.nil? ? opinions[f.id].minor_outcome : nil
        Finding.new(f, disposition, disposition == "fix_requested" && !later, evidence_of(f, rev, item_body), responses[f.id], opinions[f.id], closure)
      end
      Card.new(rev, rev.item, item_body, samples, catalogue_of(item_body), Array(item_body["sources"]), Review::Gate.check(rev),
               review && JSON.parse(review.checklist_json), blind && JSON.parse(blind.results_json), findings, back[rev.id] || [], later)
    end

    # Only a blind-solve finding about an instance has evidence; a review finding quotes the item itself.
    def evidence_of(finding, rev, item_body)
      return nil unless finding.source == "blind_solve" && finding.instance

      row = rev.instances.sort_by(&:id)[finding.instance - 1] or return nil
      view = InstanceView.new(row, item_body, finding.instance)
      accepted = Array(item_body["accept"]) + (row.accept_json.present? ? Array(JSON.parse(row.accept_json)) : [])
      answers = finding.blind_solve ? JSON.parse(finding.blind_solve.answers_json) : []
      given = Array(answers).find { |a| a.is_a?(Hash) && a["instance"] == finding.instance }
      Evidence.new(view.key, accepted.map(&:to_s).uniq, given && raw_answer(given["answer"]), given.nil? || given["dont_know"] == true)
    end

    # The solver's answer as it was written: text as is, anything structured as JSON.
    def raw_answer(value)
      value.is_a?(String) ? value : JSON.generate(value)
    end

    def catalogue_of(body)
      return Array(body["error_catalogue"]) unless body["kind"] == "testlet"

      Array(body["sub_items"]).flat_map { |s| Array(s["error_catalogue"]).map { |e| e.merge("sub_item" => s["id"]) } }
    end
  end
end
