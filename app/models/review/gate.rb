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
  module Gate
    Result = Struct.new(:approvable, :reasons, :open_findings, keyword_init: true) do
      def to_h = { approvable: approvable, reasons: reasons, open_findings: open_findings }
    end

    module_function

    def approvable?(revision) = check(revision).approvable

    def check(revision)
      reasons = []
      reasons << "validation has not passed" unless revision.status == "passed"
      reasons << "no expert review on this revision" unless revision.reviews.exists?
      reasons << "no blind solve on this revision" unless revision.blind_solves.exists?
      dispositions = ReviewFinding.dispositions
      must = revision.findings.must_be_disposed.order(:id).to_a
      open = must.reject { |f| dispositions.key?(f.id) }
      fixes = must.select { |f| dispositions[f.id] == "fix_requested" }
      reasons << "the teacher sent this revision back: a new revision is needed" if Teacher::SendBacks.sent_back?(revision)
      reasons << "#{open.size} blocker or major finding(s) without the teacher's disposition" if open.any?
      reasons << "#{fixes.size} finding(s) the teacher asked to fix: a new revision is needed" if fixes.any?
      Result.new(approvable: reasons.empty?, reasons: reasons, open_findings: open.map(&:id))
    end

    # The agent's side is done for a revision: a review and a blind solve exist.
    def worked?(revision) = revision.reviews.exists? && revision.blind_solves.exists?
  end
end
