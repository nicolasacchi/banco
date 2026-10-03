module Api
  module V1
    # GET /api/v1/briefs/:name: the authoring brief a content agent starts from.
    class BriefsController < Api::BaseController
      def show
        brief = Brief.find(params[:name])
        return render json: brief if brief

        render json: { code: "E-BRIEF-UNKNOWN", field: "name", message: "no brief named #{params[:name].to_s.first(40).inspect}",
                       next: "available: #{Brief.names.join(', ')}" }, status: :not_found
      end
    end
  end
end
