# frozen_string_literal: true

require "json"
require "stringio"
require "yaml"
require "zlib"
require "digest"
require "net/http"
require "uri"
require "fileutils"

module Maps
  # The open data the bases are built from. `bin/build-maps --fetch` downloads each upstream file at
  # a pinned address, trims it to the properties and the precision the bases need, and commits the
  # result under config/banco/data/geo/source/ with the checksum of the upstream file in
  # sources.yml. `bin/build-maps` itself never touches the network.
  module Sources
    ROOT = File.expand_path("../..", __dir__)
    DIR = File.join(ROOT, "config/banco/data/geo/source")
    MANIFEST = File.join(DIR, "sources.yml")
    NE_TAG = "v5.1.2"
    NE_URL = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/#{NE_TAG}/geojson"
    WB_URL = "https://api.worldbank.org/v2/country/all/indicator/%<indicator>s?format=json&date=%<year>d&per_page=400"
    PLEIADES_DUMP = "pleiades-places-20261011.csv.gz"
    PLEIADES_URL = "https://atlantides.org/downloads/pleiades/dumps/#{PLEIADES_DUMP}"
    PLEIADES_DATE = "2026-10-11"

    COUNTRY_PROPS = %w[ADM0_A3 ISO_A3_EH NAME NAME_IT NAME_EN NAME_ES CONTINENT SUBREGION TYPE POP_EST POP_YEAR].freeze
    NAMED_PROPS = %w[name name_en name_it name_es scalerank featurecla].freeze

    # file stem => the properties kept (and, for admin-1, which countries)
    NATURAL_EARTH = {
      "ne_110m_admin_0_countries" => { props: COUNTRY_PROPS },
      "ne_50m_admin_0_countries" => { props: COUNTRY_PROPS },
      "ne_10m_admin_1_states_provinces" => { props: %w[name name_it name_en name_es region adm0_a3], only: { "adm0_a3" => %w[ITA GRC TUR] } },
      "ne_110m_land" => { props: [] },
      "ne_50m_land" => { props: [] },
      "ne_110m_lakes" => { props: NAMED_PROPS },
      "ne_50m_lakes" => { props: NAMED_PROPS },
      "ne_110m_rivers_lake_centerlines" => { props: NAMED_PROPS },
      "ne_50m_rivers_lake_centerlines" => { props: NAMED_PROPS },
      "ne_110m_populated_places" => { props: %w[NAME NAMEASCII NAME_EN NAME_IT NAME_ES ADM0_A3 ADM0CAP FEATURECLA POP_MAX SCALERANK] }
    }.freeze

    WORLD_BANK = {
      "worldbank_area_2021" => { indicator: "AG.SRF.TOTL.K2", year: 2021 },
      "worldbank_population_2023" => { indicator: "SP.POP.TOTL", year: 2023 }
    }.freeze

    module_function

    def path(name) = File.join(DIR, "#{name}.json.gz")

    def manifest = YAML.safe_load_file(MANIFEST)

    # The trimmed features: [{"p" => properties, "g" => {"type" =>, "coordinates" =>}}].
    def load(name)
      @cache ||= {}
      @cache[name] ||= JSON.parse(Zlib::GzipReader.open(path(name), &:read))
    end

    def read_checked(name)
      sha = manifest.fetch("files").fetch(name).fetch("sha256")
      raise "#{name}: the trimmed file differs from sources.yml (run bin/build-maps --fetch)" unless Digest::SHA256.file(path(name)).hexdigest == sha
      load(name)
    end

    def round_coords(c, digits = 3)
      c.first.is_a?(Numeric) ? c.first(2).map { |v| v.round(digits) } : c.map { |x| round_coords(x, digits) }
    end

    def gzip(text)
      io = StringIO.new
      gz = Zlib::GzipWriter.new(io, 9)
      gz.mtime = Time.at(0)
      gz.write(text)
      gz.close
      io.string
    end

    def download(url, cache, filename)
      FileUtils.mkdir_p(cache)
      target = File.join(cache, filename)
      return target if File.exist?(target)
      uri = URI(url)
      5.times do
        res = Net::HTTP.get_response(uri)
        case res
        when Net::HTTPSuccess
          File.binwrite(target, res.body)
          return target
        when Net::HTTPRedirection then uri = URI(res["location"])
        else raise "#{url}: #{res.code}"
        end
      end
      raise "#{url}: too many redirects"
    end

    def trim_feature(f, spec)
      props = f["properties"] || {}
      return nil if spec[:only] && spec[:only].any? { |k, vals| !vals.include?(props[k]) }
      kept = spec[:props].to_h { |k| [ k, props[k] ] }.compact
      { "p" => kept, "g" => { "type" => f["geometry"]["type"], "coordinates" => round_coords(f["geometry"]["coordinates"]) } }
    end

    def licence_of(name)
      name.start_with?("worldbank") ? "CC BY 4.0" : "public domain (Natural Earth)"
    end

    # Writes every trimmed file and sources.yml. `cache` holds the upstream downloads.
    def fetch!(cache)
      FileUtils.mkdir_p(DIR)
      files = {}
      NATURAL_EARTH.each do |stem, spec|
        url = "#{NE_URL}/#{stem}.geojson"
        raw = download(url, cache, "#{stem}.geojson")
        data = JSON.parse(File.read(raw))
        feats = data["features"].filter_map { |f| trim_feature(f, spec) }
        write_trimmed(files, stem, { "features" => feats }, url, Digest::SHA256.file(raw).hexdigest)
      end
      WORLD_BANK.each do |stem, spec|
        url = format(WB_URL, spec)
        raw = download(url, cache, "#{stem}.json")
        rows = JSON.parse(File.read(raw)).last.filter_map { |r| [ r["countryiso3code"], r["value"] ] if r["value"] && !r["countryiso3code"].to_s.empty? }
        write_trimmed(files, stem, { "year" => spec[:year], "values" => rows.sort.to_h }, url, Digest::SHA256.file(raw).hexdigest)
      end
      manifest = {
        "natural_earth_version" => NE_TAG,
        "note" => "Written by bin/build-maps --fetch. sha256 is of the trimmed file here; upstream_sha256 of the file at the url.",
        "files" => files.sort.to_h
      }
      File.write(MANIFEST, YAML.dump(manifest))
    end

    def write_trimmed(files, stem, data, url, upstream_sha)
      bytes = gzip(JSON.generate(data))
      File.binwrite(path(stem), bytes)
      files[stem] = {
        "url" => url, "sha256" => Digest::SHA256.hexdigest(bytes), "upstream_sha256" => upstream_sha,
        "licence" => licence_of(stem), "bytes" => bytes.bytesize
      }
    end
  end
end
