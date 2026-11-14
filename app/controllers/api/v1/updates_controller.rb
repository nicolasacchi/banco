module Api
  module V1
    # What a self-updating bot reads (D-330), for any token role: what changed (GET /api/v1/updates), the two docs it lives
    # by (GET /api/v1/docs/:name, bot or api) and the CLI's release build of this image (GET /api/v1/cli/:file). The names
    # of a doc and of a binary come from allowlists (Updates::DOCS, dist/SHA256SUMS); no path is built from the request.
    class UpdatesController < Api::BaseController
      # GET /api/v1/updates[?since=D-NNN]
      def show
        since = nil
        if params.key?(:since)
          since = Updates.since_number(params[:since])
          return refuse("E-FILES", "since", "since is a decision number such as D-327", "banco changes --since D-327", 422) unless since
        end
        render json: Updates.summary(since: since)
      end

      # GET /api/v1/docs/:name
      def doc
        doc = Updates.doc(params[:name])
        return render json: doc if doc

        refuse("E-NOT-FOUND", "name", "no doc named #{params[:name].to_s.first(40).inspect}", "available: #{Updates::DOCS.keys.join(', ')}", 404)
      end

      # GET /api/v1/cli/:file: the binary, with its sha256 in X-Banco-Sha256.
      def cli
        file, path = Updates.cli_file(params[:file])
        unless file
          return refuse("E-NOT-FOUND", "file", "this server has no release build named #{params[:file].to_s.first(40).inspect}",
                        "banco self-update --check lists the files", 404)
        end

        response.set_header("X-Banco-Sha256", file.sha256)
        send_file path, filename: file.name, type: "application/octet-stream", disposition: "attachment"
      end
    end
  end
end
