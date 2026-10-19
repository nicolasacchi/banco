module Review
  # The mechanical half of the teacher's approval (A-05): whether an item revision
  # may be approved. approvable? is true when
  #
  #   - its validation passed,
  #   - an expert review and a blind solve exist on this exact revision, and
  #   - every blocker and major finding of the revision has a disposition of the
  #     teacher (decision kind dispose_finding), none of them a fix request, and
  #   - the teacher has not sent the revision back (send_back_item, "Rimanda").
  #
  # There is no agent verdict and no waiver: the agents report and the teacher
  # decides (firm rule 2). A fix request means the revision is to be replaced, so it
  # keeps the gate shut.
  #
  # A review or a blind solve counts only when its session ran on another TRUE model than every author of the item
  # (D-316, Providers.independent?, read each time with AgentSession#model, which a correction can change).
  module Gate
    Result = Struct.new(:approvable, :reasons, :open_findings, keyword_init: true) do
      def to_h = { approvable: approvable, reasons: reasons, open_findings: open_findings }
    end

    module_function

    def approvable?(revision) = check(revision).approvable

    def check(revision)
      reasons = []
      reasons << "validation has not passed" unless revision.status == "passed"
      reasons << review_reason(revision.reviews, revision.counting_reviews, "expert review")
      reasons << review_reason(revision.blind_solves, revision.counting_blind_solves, "blind solve")
      reasons.compact!
      dispositions = ReviewFinding.dispositions
      must = revision.findings.must_be_disposed.order(:id).to_a
      open = must.reject { |f| dispositions.key?(f.id) }
      fixes = must.select { |f| dispositions[f.id] == "fix_requested" }
      reasons << "the teacher sent this revision back: a new revision is needed" if Teacher::SendBacks.sent_back?(revision)
      reasons << "#{open.size} blocker or major finding(s) without the teacher's disposition" if open.any?
      reasons << "#{fixes.size} finding(s) the teacher asked to fix: a new revision is needed" if fixes.any?
      Result.new(approvable: reasons.empty?, reasons: reasons, open_findings: open.map(&:id))
    end

    # The agent's side is done for a revision: a review and a blind solve exist that count (D-316: independent
    # by the true model of the session).
    def worked?(revision) = revision.counting_reviews.any? && revision.counting_blind_solves.any?

    # nil when a row counts. The words matter: Teacher::Wording turns them into Italian.
    def review_reason(all, counting, what)
      return nil if counting.any?
      return "no #{what} on this revision" unless all.exists?

      "no independent #{what} on this revision: the session that filed it runs on the same model as an author of the item"
    end
  end
end
