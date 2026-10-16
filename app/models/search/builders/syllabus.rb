module Search
  module Builders
    # The lines of the programmes (syllabus_lines), one document per line.
    module Syllabus
      module_function

      def call
        SyllabusLine.includes(:syllabus_source).order(:id).map do |line|
          source = line.syllabus_source
          Doc.build(kind: "syllabus_line", key: "#{source.key}:#{line.number}", title: I18n.t("search.syllabus_title", source: source.key, number: line.number),
                    body: line.text, status: line.origin, anchor: line.number)
        end
      end
    end
  end
end
