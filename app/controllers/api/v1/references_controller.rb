module Api
  module V1
    # GET /api/v1/references and /api/v1/references/:key: the imported reference
    # texts an item may quote through prompt.quote {ref, text} (E-QUOTE-REF). Read
    # only: agents cannot import a text (the operator does, D-074).
    class ReferencesController < Api::BaseController
      def index
        rows = ReferenceText.order(:key).map { |r| summary(r) }
        render json: { rows: rows }
      end

      def show
        reference = ReferenceText.find_by(key: params[:key].to_s)
        return refuse("E-NOT-FOUND", "key", "no reference text #{params[:key].to_s.first(40).inspect}", "banco reference list", 404) unless reference

        render json: summary(reference).merge(body: reference.body)
      end

      private

      def summary(r)
        { key: r.key, title: r.title, source_url: r.source_url, sha256: r.sha256, words: r.body.split.size }
      end
    end
  end
end
