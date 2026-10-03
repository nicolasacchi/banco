module Api
  module V1
    # GET /api/v1/schema: the command contract the CLI embeds.
    class SchemaController < Api::BaseController
      def show
        render json: Contract.raw
      end
    end
  end
end
