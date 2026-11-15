module Api
  module V1
    # The shots of an item revision as the student sees it on a phone (D-336): one WebP per stored instance at 390 px, drawn on demand in the server's Chrome
    # (RenderItemRevisionJob), for the reviewer and the blind solver (`banco item shots REV --dir D`). The content roles request a render (POST); every token
    # role reads the status, the list and the files; a bot_read or teacher token cannot request (Api::BaseController refuses its POST). Nothing here decides,
    # and a render is an aid: no gate reads it.
    class ItemShotsController < Api::BaseController
      before_action :load_revision

      SEED_NOTE = "The choices of a choice item, the rows of a matching and the steps of an ordering are shown shuffled with a fixed seed (the shot's `seed`), as the " \
                  "student's page shuffles them; `shown_order` lists the stored ids in the order drawn, so the position n of a picture (the number on an option) is " \
                  "shown_order[column][n-1]. `width` is in CSS px (the device scale is 1)."

      # GET /api/v1/item-revisions/:revision/shots
      def index
        latest = ItemRender.latest_for(@revision)
        verdict = ItemRender.verdict_for(@revision)
        out = { revision_id: @revision.id, item: @revision.item.key, status: latest ? latest.status : "none", instances: Items::ShotPresentation.instances(@revision).count }
        out[:render_id] = latest.id if latest
        out[:requested_at] = latest.created_at.utc.iso8601 if latest
        out[:stale] = true if latest && Items::ShotRequest.stale?(latest)
        out[:message] = latest.result["message"] if latest&.status == "error"
        if verdict
          out.merge!(shots_from: verdict.id, viewport: verdict.result["viewport"], instances_drawn: verdict.result["instances"], instances_total: verdict.result["instances_total"],
                     elapsed_seconds: verdict.result["elapsed_seconds"], errors: findings(verdict), notes: notes(verdict), seed_note: SEED_NOTE, shots: shots(verdict))
        else
          out.merge!(errors: [], notes: [], shots: [])
        end
        out[:next] = next_step(latest)
        render json: out
      end

      # POST /api/v1/item-revisions/:revision/shots[?force=1]
      def create
        unless Items::ShotPresentation.instances(@revision).exists?
          return refuse("E-ITEM-NOT-PASSED", "revision", "revision #{@revision.id} has no instance to draw (status #{@revision.status})", "banco work status #{@revision.id} --wait", 422)
        end

        force = ActiveModel::Type::Boolean.new.cast(params[:force]) == true
        if dry_run?
          needed = Items::ShotRequest.new(@revision, force: force, now: Time.current).needed?(ItemRender.latest_for(@revision))
          return render json: { dry_run: true, would_enqueue: needed, status: ItemRender.latest_for(@revision)&.status || "none" }
        end

        result = Items::ShotRequest.call(@revision, force: force)
        status = result.enqueued ? :accepted : :ok
        body = { revision_id: @revision.id, item: @revision.item.key, enqueued: result.enqueued, status: result.row.status, render_id: result.row.id, next: next_step(result.row) }
        body[:why_not] = result.row.status == "queued" ? "a render is already queued" : "the revision has been rendered: add --force (force=1) to draw it again" unless result.enqueued
        render json: body, status: status
      end

      # GET /api/v1/item-revisions/:revision/shots/:sha
      def show
        known = ItemRender.where(item_revision_id: @revision.id).any? { |r| r.shots.any? { |s| s["sha256"] == params[:sha] } }
        return refuse("E-NOT-FOUND", "sha", "revision #{@revision.id} has no such image", "banco item shots #{@revision.id} --dir DIR", 404) unless known

        bytes = LessonShots.read(params[:sha])
        return refuse("E-NOT-FOUND", "sha", "the image was removed by the purge (immagine rimossa)", "banco item shots #{@revision.id} --dir DIR --force", 404) unless bytes

        send_data bytes, type: "image/webp", disposition: "inline"
      end

      private

      def shots(row)
        row.shots.map do |s|
          s.slice("instance", "seed", "shown_order", "viewport", "width", "height", "scale", "sha256", "bytes").merge(
            "available" => LessonShots.exist?(s["sha256"]), "path" => "/api/v1/item-revisions/#{@revision.id}/shots/#{s['sha256']}"
          )
        end
      end

      def findings(row) = row.errors_list.reject { |e| e["level"] == "note" }

      def notes(row) = row.errors_list.select { |e| e["level"] == "note" }

      def next_step(row)
        case row&.status
        when "passed", "failed" then "look at every picture, instance by instance (390 px is the phone): banco item shots #{@revision.id} --dir DIR"
        when "queued" then "the render is queued; ask again: banco item shots #{@revision.id} --dir DIR --wait"
        else "request it: banco item shots #{@revision.id} --dir DIR --wait"
        end
      end

      def load_revision
        @revision = ItemRevision.find_by(id: params[:revision])
        return if @revision

        refuse("E-NOT-FOUND", "revision", "no item revision #{params[:revision].to_s.first(20).inspect}", "banco work open ITEM", 404)
      end
    end
  end
end
