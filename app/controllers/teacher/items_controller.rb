module Teacher
  # One item revision as the teacher reads it: samples of its instances. Opening it
  # is the app_event teacher_viewed_item that the approval of the entry test needs
  # (B-07). The student's computer only reads: no event is written there.
  class ItemsController < ApplicationController
    layout "teacher"
    before_action :require_teacher!

    SAMPLES = 4

    def show
      @revision = ItemRevision.find_by(id: params[:revision_id]) or return head(:not_found)

      @body = JSON.parse(@revision.body_json)
      @samples = @revision.instances.order(:id).limit(SAMPLES).map { |i| JSON.parse(i.display_json) }
      return if request.cookies[DecisionRecorder::DEVICE_COOKIE].present?

      AppEvent.create!(kind: "teacher_viewed_item", payload_json: { item_revision_id: @revision.id }.to_json)
    end
  end
end
