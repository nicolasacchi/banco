module Review
  # The figures an item's instances show (D-320), found in the displays the reviewer or the blind solver reads
  # (the item's own prompt figure, an instance's, a testlet sub item's). Each distinct SVG asset is one file,
  # figure-1.png, figure-2.png ... in order of first appearance, and says which instances show it; the display
  # keeps only the alt text and the file name (the solver) or its figure plus the file name (the reviewer).
  class Figures
    Entry = Struct.new(:name, :asset, :alt_it, :instances)

    def initialize(files)
      @files = files
      @entries = {}
    end

    def empty? = @entries.empty?

    # The display with each figure marked with its file; +keep+ leaves the figure's own members in place.
    def mark(node, number, keep: false)
      case node
      when Hash
        node.to_h do |key, value|
          if key == "figure" && value.is_a?(Hash) && value["asset"].is_a?(String)
            entry = entry_for(value, number)
            [ key, keep ? value.merge("file" => entry.name) : { "alt_it" => value["alt_it"], "file" => entry.name }.compact ]
          else
            [ key, mark(value, number, keep: keep) ]
          end
        end
      when Array then node.map { |v| mark(v, number, keep: keep) }
      else node
      end
    end

    # [{name, alt_it, instances, sha256, width, height, png_base64}]; an asset the revision does not hold is
    # listed with missing: true so that the agent reports it. Raises FigureImage::Unavailable when Chrome cannot draw.
    def files
      @entries.values.map do |entry|
        row = { name: entry.name, alt_it: entry.alt_it, instances: entry.instances }.compact
        svg = @files[entry.asset]
        next row.merge(missing: true) if svg.nil?

        image = FigureImage.png(svg)
        row.merge(sha256: image.sha256, width: image.width, height: image.height, png_base64: Base64.strict_encode64(image.bytes))
      end
    end

    private

    def entry_for(figure, number)
      entry = (@entries[figure["asset"]] ||= Entry.new("figure-#{@entries.size + 1}.png", figure["asset"], figure["alt_it"], []))
      entry.instances << number unless entry.instances.include?(number)
      entry
    end
  end
end
