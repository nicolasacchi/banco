module Teacher
  # The student's comments (D-304). The page: the teacher sees every comment (text, place, history) with the actions
  # Rispondi, Segna letto, Chiudi and Riapri; a guest sees the counts only, never a text or a reply. The actions are
  # POSTs on the web listener, written by Comments::Responder under the decisions' guards (flag, teacher, CSRF, not
  # the student's computer); nothing else writes a reply. Each action answers a redirect back to this page.
  class CommentsController < Teacher::BaseController
    skip_forgery_protection only: %i[reply read resolve reopen]
    before_action :check_csrf, only: %i[reply read resolve reopen]

    ACTIONS = { "reply" => "reply", "read" => "read", "resolve" => "resolved", "reopen" => "reopened" }.freeze

    def show
      @counts = Comments::Inbox.counts
      return if reader_only? # a guest: the counts only, no row, no text

      @inbox = Comments::Inbox.new(params.permit(*Comments::Inbox::FILTERS).to_h.symbolize_keys)
      @rows = @inbox.rows
      @subjects = Subject.order(:position)
    end

    ACTIONS.each do |action, kind|
      define_method(action) do
        Comments::Responder.call(request: request, comment_id: params[:comment_id], kind: kind, text_it: params[:text_it])
        redirect_to back_path, status: :see_other, notice: I18n.t("teacher.comments.done.#{kind}")
      rescue DecisionRecorder::Refused
        render plain: "Forbidden", status: :forbidden
      rescue DecisionRecorder::Missing
        render plain: "Not Found", status: :not_found
      rescue DecisionRecorder::Invalid => e
        redirect_to back_path, status: :see_other, alert: e.reasons.map { |r| Teacher::Wording.italian(r) }.join(" ")
      end
    end

    private

    def check_csrf
      request.env[DecisionRecorder::CSRF_KEY] = any_authenticity_token_valid?
    end

    def back_path
      back = params[:back].to_s
      back.match?(%r{\A/teacher/comments(?:\?[A-Za-z0-9_=&.\-]*)?\z}) ? back : "/teacher/comments"
    end
  end
end
