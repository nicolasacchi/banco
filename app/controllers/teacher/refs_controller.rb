module Teacher
  # The permalink of a skill key or an item key (D-218): the same card as the popover, whole,
  # for printing, sharing and for the links the teacher's AI agent writes in reports. Read-only.
  class RefsController < Teacher::BaseController
    def show
      @key = params[:key].to_s
      @card = helpers.teacher_refs.resolve(@key)
      render :not_found, status: :not_found unless @card
    end
  end
end
