module Teacher
  # "Prova": one instance of one item, drawn by the student's own renderer, so the teacher
  # sees what S would see. Nothing is graded or stored: the page has no answer endpoint.
  class ItemPlaysController < Teacher::BaseController
    def show
      @revision = ItemRevision.find_by(id: params[:revision_id]) or return head(:not_found)

      @count = @revision.instances.count
      @n = [ [ params[:n].to_i, 1 ].max, [ @count, 1 ].max ].min
      @unit = "#{@revision.item.subject.key}:test"
      skill = JSON.parse(@revision.body_json)["skill"].to_s
      @back_path = if skill.match?(/\A[a-z0-9][a-z0-9.\-]*\z/)
        teacher_test_skill_path(key: @revision.item.subject.key, skill: skill)
      else
        teacher_test_path(key: @revision.item.subject.key)
      end
    end

    # The presentation of the n-th instance as the browser is told it (ItemPresenter), not shuffled.
    def data
      revision = ItemRevision.find_by(id: params[:revision_id]) or return head(:not_found)

      instance = revision.instances.order(:id).offset([ params[:n].to_i - 1, 0 ].max).first or return head(:not_found)
      body = JSON.parse(revision.body_json)
      shuffled = Diagnosis::Conductor.rekey(instance, body, "preview|#{revision.id}|#{instance.id}|#{SecureRandom.hex(4)}")
      served = ItemServed.new(item_instance: instance, skill_key: body["skill"].to_s, shown_order_json: shuffled.shown_order.to_json)
      payload = Diagnosis::ItemPresenter.new(served: served, number: 1, subject: revision.item.subject).as_json
      response.headers["Cache-Control"] = "no-store"
      render json: payload
    end
  end
end
