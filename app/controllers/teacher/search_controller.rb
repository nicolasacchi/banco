module Teacher
  # The teacher's search (D-299): every content kind and every status, the latest revision of each object, with filters. The
  # teacher alone has a second tab, the answers of one student (`?student=KEY` as everywhere on the teacher's pages); a guest asking
  # for it gets 403, as does anyone asking for a kind the scope does not know. Read-only; nothing is recorded.
  class SearchController < Teacher::BaseController
    MAX_QUERY = 200
    LIMIT = 50

    def show
      @query = params[:q].to_s.squish.first(MAX_QUERY)
      @answers_tab = params[:tab] == "answers"
      return head(:forbidden) if @answers_tab && !current_identity&.teacher?

      @subject_filter = params[:subject].to_s.presence
      @kind = params[:kind].to_s.presence
      @status = params[:status].to_s.presence
      @scope = @answers_tab ? Search::Scope::Staff.new(answers_for: viewed_student&.key || "-") : Search::Scope::Staff.new
      kinds = @answers_tab ? [ "student_answer" ] : [ @kind ].compact
      return unless @query.present?

      @result = Search::Engine.new(scope: @scope).call(@query, subject: @subject_filter, kind: kinds, status: @status, limit: LIMIT)
    rescue Search::Engine::BadKind
      head :forbidden
    end

    helper_method :kind_choices

    def kind_choices = Search::Doc::STUDENT_KINDS + Search::Doc::STAFF_KINDS
  end
end
