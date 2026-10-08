module Api
  module V1
    # GET /api/v1/items?subject=KEY[&current=1][&kind=practice|diagnosis]: every revision of the items of a subject
    # with the status of its latest validation, whether it is the current (latest)
    # revision of its item, and how many reviews and blind solves it has. Read only:
    # it tells a reviewer which revision ids to open (`banco review open ID`) and an
    # author which revision ids to pin (skill, component, instances, low_guess_instances; on current revisions).
    class ItemsController < Api::BaseController
      def index
        subject = nil
        if params[:subject].present?
          subject = Subject.find_by(key: params[:subject].to_s)
          return refuse("E-NOT-FOUND", "subject", "no subject #{params[:subject].to_s.first(40).inspect}", "banco status", 404) unless subject
        end

        kind = params[:kind].to_s
        unless kind.in?(%w[practice diagnosis]) || kind.empty?
          return refuse("E-NOT-FOUND", "kind", "kind is practice or diagnosis, not #{kind.first(40).inspect}", "banco items list --kind practice", 404)
        end

        items = subject ? Item.where(subject: subject) : Item.all
        items = items.practice if kind == "practice"
        items = items.diagnosis if kind == "diagnosis"
        items = items.includes(:subject, revisions: %i[validations reviews blind_solves]).order(:id)
        only_current = params[:current].to_s.in?(%w[1 true])
        rows = items.flat_map do |item|
          latest = item.revisions.max_by(&:seq)
          item.revisions.sort_by(&:seq).filter_map do |rev|
            current = rev.id == latest.id
            next if only_current && !current

            status = rev.validations.max_by(&:seq)&.display_status || "validating"
            # An older revision never waits for a verifier: only the current one is actionable (D-206).
            status = "superseded" if !current && status == "awaiting_verifier"
            { item: item.key, subject: item.subject.key, kind: item.kind, revision_id: rev.id, seq: rev.seq,
              status: status, current: current,
              reviews: rev.reviews.size, blind_solves: rev.blind_solves.size }.merge(current ? blueprint_facts(rev) : {})
          end
        end
        render json: { rows: rows }
      end

      private

      # What an author needs to pin a revision in a blueprint: its skill, component,
      # expected seconds, and how many instances it has and how many are hard to guess
      # (D-129). Additive fields: the rest of the row is unchanged.
      def blueprint_facts(rev)
        body = JSON.parse(rev.body_json)
        skill = body["kind"] == "testlet" ? Array(body["sub_items"]).first&.dig("skill") : body["skill"]
        instances = Diagnosis::PlanLoader.instances_of_revision(rev)
        { skill: skill, component: body["component"], expected_seconds: body["expected_seconds"],
          instances: instances.size, low_guess_instances: instances.count(&:low_guess) }
      rescue JSON::ParserError
        {}
      end
    end
  end
end
