module Review
  # The figures an item's instances show (D-320), found in the displays the reviewer or the blind solver reads
  # (the item's own prompt figure, an instance's, a testlet sub item's). Each distinct picture is one file,
  # figure-1.png, figure-2.png ... in order of first appearance, with the instances that show it. The display
  # keeps only the alt text and the file name (the solver) or its figure plus the file name (the reviewer).
  #
  # The picture is made from the bytes the student gets: the figure is resolved as Items::Part does (D-321),
  # through Items::Figures (same digest, same refusal rules) and read from its stored copy. A figure the student
  # would not be shown (a refused or absent asset, a digest with no stored file) is listed with missing: true,
  # never drawn. A figure with neither asset nor digest is only its alt text.
  class Figures
    SHA256 = /\A[0-9a-f]{64}\z/
    Entry = Struct.new(:name, :key, :sha, :alt_it, :instances)

    def initialize(files)
      @files = files
      @entries = {}
      @stored = {}
    end

    def empty? = @entries.empty?

    # The display with each figure marked with its file; +keep+ leaves the figure's own members in place.
    def mark(node, number, keep: false)
      case node
      when Hash
        node.to_h do |key, value|
          if key == "figure" && value.is_a?(Hash)
            entry = entry_for(value, number)
            if entry
              [ key, keep ? value.merge("file" => entry.name) : { "alt_it" => value["alt_it"], "file" => entry.name }.compact ]
            else
              [ key, keep ? value : { "alt_it" => value["alt_it"] }.compact ]
            end
          else
            [ key, mark(value, number, keep: keep) ]
          end
        end
      when Array then node.map { |v| mark(v, number, keep: keep) }
      else node
      end
    end

    # [{name, alt_it, instances, sha256, width, height, png_base64}]; one the student would not be shown has
    # missing: true. All the pictures are drawn in one Chrome session; raises FigureImage::Unavailable (or Busy).
    def files
      entries = @entries.values
      svgs = entries.map { |e| e.sha && stored_svg(e.sha) }
      images = FigureImage.png_all(svgs.compact).each
      entries.zip(svgs).map do |entry, svg|
        row = { name: entry.name, alt_it: entry.alt_it, instances: entry.instances }.compact
        next row.merge(missing: true) if svg.nil?

        image = images.next
        row.merge(sha256: image.sha256, width: image.width, height: image.height, png_base64: Base64.strict_encode64(image.bytes))
      end
    end

    private

    # The digest of the picture the student gets for this figure, or nil when they get none.
    def digest(figure)
      sha = figure["sha256"].to_s
      return sha if SHA256.match?(sha) && stored_svg(sha)

      figure["asset"].is_a?(String) ? Items::Figures.digest_for(figure["asset"], @files) : nil
    end

    # The stored copy of a digest (what ItemAssetsController serves), or nil.
    def stored_svg(sha)
      @stored[sha] = read_stored(sha) unless @stored.key?(sha)
      @stored[sha]
    end

    def read_stored(sha)
      path = ItemAssetsController.directory.join("#{sha}.svg")
      return nil unless path.file?

      text = path.read
      Digest::SHA256.hexdigest(text) == sha ? text : nil
    end

    def entry_for(figure, number)
      return nil unless figure["asset"].is_a?(String) || SHA256.match?(figure["sha256"].to_s)

      sha = digest(figure)
      key = sha || "missing:#{figure['asset'] || figure['sha256']}"
      entry = (@entries[key] ||= Entry.new("figure-#{@entries.size + 1}.png", key, sha, figure["alt_it"], []))
      entry.instances << number unless entry.instances.include?(number)
      entry
    end
  end
end
