module Api
  module V1
    # GET /api/v1/syllabus/:source/lines?from=N&to=M: the lines of an imported
    # programme, so that a graph can cite them exactly (E-SOURCE). Transcriber
    # lines are listed but marked citable: false. marker is the line's own star;
    # block_marker (and block_marker_line, the header it comes from) the one a line
    # inherits from the header above it; section is the "## " heading it sits under.
    class SyllabusController < Api::BaseController
      MAX_LINES = 400

      def lines
        source = SyllabusSource.find_by(key: params[:source].to_s)
        return refuse("E-NOT-FOUND", "source", "no programme #{params[:source].to_s.first(40).inspect}", "banco skill-graph open --subject KEY (lists the sources)", 404) unless source

        from = integer(params[:from], 1)
        to = integer(params[:to], source.line_count)
        return refuse("E-FILES", "range", "from and to are line numbers, from at most to", "banco syllabus lines --source #{source.key} --from 1 --to 50", 422) if from.nil? || to.nil? || from > to
        return refuse("E-FILES", "range", "at most #{MAX_LINES} lines at a time", "banco syllabus lines --source #{source.key} --from #{from} --to #{from + MAX_LINES - 1}", 422) if to - from + 1 > MAX_LINES

        upto = SyllabusLine.where(syllabus_source: source, number: ..to).order(:number).to_a
        inherited = Syllabus::BlockMarker.call(upto)
        sections = Syllabus::Sections.call(upto)
        rows = SyllabusLine.where(syllabus_source: source, number: from..to).order(:number).map do |l|
          block = inherited[l.number]
          { line: l.number, text: l.text, origin: l.origin, citable: l.citable?, marker: l.marker,
            block_marker: block&.fetch(:marker), block_marker_line: block&.fetch(:from), section: sections[l.number] }.compact
        end
        render json: { source: source.key, lines: source.line_count, from: from, to: to, rows: rows }
      end

      private

      def integer(value, default)
        return default if value.blank?

        value.to_s.match?(/\A\d+\z/) && value.to_i.positive? ? value.to_i : nil
      end
    end
  end
end
