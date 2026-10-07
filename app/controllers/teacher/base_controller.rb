module Teacher
  # The teacher's pages: read-only HTML on the web listener, for the trusted teacher and the guest (D-217).
  # Every write is a decision posted to Teacher::DecisionsController, or the heartbeat of
  # Teacher::ActivityController. Pages set @unit, the unit of their measured minutes.
  class BaseController < ApplicationController
    layout "teacher"
    include ViewedStudent
    before_action :require_reader!

    private

    def subject!
      @subject = Subject.find_by(key: params[:key].to_s)
      head(:not_found) unless @subject
      @subject
    end

    # Opening a pinned item's screen is what the approval gate calls "opened in the preview".
    # The student's own computer and a guest only read: nothing is written there.
    def record_views(revision_ids)
      return if request.cookies[DecisionRecorder::DEVICE_COOKIE].present? || !current_identity&.teacher?

      seen = Approval::BlueprintGate.viewed_ids
      (revision_ids - seen.to_a).each do |id|
        AppEvent.create!(kind: "teacher_viewed_item", payload_json: { item_revision_id: id }.to_json)
      end
    end
  end
end
