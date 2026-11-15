module Api
  module V1
    # View links over the API (D-332): a bot_read or teacher token creates the temporary URL that opens the teacher's pages
    # read-only (the guest role, on the view listener), lists its own links and revokes them. The one POST a bot_read token
    # may send (reader_grants): the write only grants reading, never wider than the token's own, and nothing is decided, so
    # creation is immediate, not a dry run. The URL is in the answer that creates the link and nowhere else: only the
    # sha256 of its token is stored.
    class ViewLinksController < Api::BaseController
      self.reader_grants = true

      before_action { require_token_roles("bot_read", "teacher") }

      # POST /api/v1/view-links {path?, minutes?}
      def create
        unless ViewLinks.enabled?
          return refuse("E-VIEW-DISABLED", "view_links", "view links are off: the operator sets BANCO_VIEW_LINKS_ENABLED=1 and BANCO_VIEW_URL", "ask the operator", 503)
        end

        body = request.raw_post.blank? ? {} : (parse_json_body or return)
        link, raw = ViewLinks.create!(token: registry_token, path: body["path"], minutes: body["minutes"])
        render json: { id: link.id, url: link.url(raw), path: link.path, expires_at: link.expires_at.utc.iso8601,
                       minutes: ((link.expires_at - link.created_at) / 60).round }, status: :created
      rescue ViewLinks::Invalid => e
        refuse("E-VIEW-PATH", e.field, e.message, "banco view-link new --path /teacher --minutes #{ViewLinks::DEFAULT_MINUTES}", 422)
      rescue ViewLinks::Limit => e
        refuse("E-VIEW-LIMIT", "view_links", e.message, "banco view-link list, then banco view-link revoke ID", 429)
      end

      # GET /api/v1/view-links: this token's newest ViewLinks::LIST_LIMIT links, newest first; never the URL.
      def index
        token = registry_token
        links = ViewLinks.for_token(token).to_a
        usable = ViewLinks.token_usable?(token)
        redemptions = ViewLinkRedemption.where(view_link_id: links.map(&:id)).group(:view_link_id).count
        render json: { links: links.map { |l| row(l, redemptions.fetch(l.id, 0), usable) } }
      end

      # POST /api/v1/view-links/:id/revoke: idempotent; a link of another token is not found.
      def revoke
        token = registry_token
        link = ViewLink.find_by(id: params[:id], api_token_id: token.id)
        return refuse("E-NOT-FOUND", "id", "no view link #{params[:id]} for this token", "banco view-link list", 404) unless link

        revocation = ViewLinks.revoke!(link, by: token)
        render json: { id: link.id, revoked: true, revoked_at: revocation.created_at.utc.iso8601 }
      end

      # POST /api/v1/view-links/revoke-all (D-333): revokes every link of this token that is still open; another token's links
      # are not touched. Idempotent: a second call finds none and answers an empty list.
      def revoke_all
        ids = ViewLinks.revoke_all!(registry_token)
        render json: { revoked: ids, count: ids.size }
      end

      private

      # The registry row of the request's token (the request passed authentication, so it exists).
      def registry_token = @registry_token ||= ApiToken.find_by!(public_id: @token.id)

      def row(link, redemptions, token_usable)
        { id: link.id, path: link.path, created_at: link.created_at.utc.iso8601, expires_at: link.expires_at.utc.iso8601,
          active: link.active?(token_usable: token_usable), revoked: link.revoked?, redemptions: redemptions }
      end
    end
  end
end
