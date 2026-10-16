module Search
  module Builders
    # The imported reference texts (D-074), one document per article ("Art. N", the Constitution and the Codice civile) or, for a
    # text with no articles, one per run of paragraphs.
    module References
      ARTICLE = /^[ \t]*(?:Art\.?|Articolo)[ \t]*(\d+[a-z0-9-]*)\b/i
      CHUNK = 1500

      module_function

      def call
        ReferenceText.order(:id).flat_map { |reference| articles(reference) }
      end

      def articles(reference)
        starts = reference.body.to_enum(:scan, ARTICLE).map { Regexp.last_match }
        chunks = if starts.empty?
          paragraphs(reference.body).each_with_index.map { |text, i| [ "p#{i + 1}", nil, text ] }
        else
          starts.each_with_index.map do |m, i|
            stop = starts[i + 1]&.begin(0) || reference.body.length
            [ "art-#{m[1].downcase}", m[1], reference.body[m.begin(0)...stop] ]
          end
        end
        chunks.map do |anchor, number, text|
          title = number ? "#{reference.title} · Art. #{number}" : reference.title
          Doc.build(kind: "reference_article", key: reference.key, title: title, body: text.squish, anchor: anchor, status: "imported")
        end
      end

      def paragraphs(body)
        out = [ +"" ]
        body.split(/\n{2,}/).each do |paragraph|
          out << +"" if out.last.length + paragraph.length > CHUNK && !out.last.empty?
          out.last << "#{paragraph}\n\n"
        end
        out.reject { |t| t.strip.empty? }
      end
    end
  end
end
