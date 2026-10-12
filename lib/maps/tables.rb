# frozen_string_literal: true

require "yaml"
require_relative "sources"

module Maps
  # The vetted tables made from the sources: geo/names (id to Italian name) and geo/countries (area
  # and population with year and source). `bin/build-maps --fetch` writes them; the tests read them.
  module Tables
    ROOT = Sources::ROOT
    DATA = File.join(ROOT, "config/banco/data")
    NAMES = File.join(DATA, "geo/names.yml")
    COUNTRIES = File.join(DATA, "geo/countries.yml")
    OVERRIDES = File.join(DATA, "geo/names_overrides.yml")

    CONTINENTS = {
      "africa" => [ "Africa", "Africa", "África" ],
      "asia" => [ "Asia", "Asia", "Asia" ],
      "europe" => [ "Europa", "Europe", "Europa" ],
      "north_america" => [ "America del Nord", "North America", "América del Norte" ],
      "south_america" => [ "America del Sud", "South America", "América del Sur" ],
      "oceania" => [ "Oceania", "Oceania", "Oceanía" ],
      "antarctica" => [ "Antartide", "Antarctica", "Antártida" ]
    }.freeze

    # Our own label positions for the oceans ([lon, lat] each): the first inside a base is used.
    OCEANS = {
      "atlantic" => [ [ "Oceano Atlantico", "Atlantic Ocean", "Océano Atlántico" ], [ [ -30, 15 ], [ -35, -20 ], [ -38, -35 ], [ -25, 50 ], [ -10, -5 ], [ -18, 25 ] ] ],
      "pacific" => [ [ "Oceano Pacifico", "Pacific Ocean", "Océano Pacífico" ], [ [ -150, 0 ], [ 165, 10 ], [ -120, -30 ], [ -79, -38 ], [ 150, -35 ], [ -170, 40 ], [ 155, -10 ] ] ],
      "indian" => [ [ "Oceano Indiano", "Indian Ocean", "Océano Índico" ], [ [ 80, -15 ], [ 68, 5 ], [ 100, -20 ] ] ],
      "arctic" => [ [ "Oceano Glaciale Artico", "Arctic Ocean", "Océano Glacial Ártico" ], [ [ 0, 85 ], [ 90, 82 ], [ -140, 80 ], [ 0, 76 ] ] ],
      "southern" => [ [ "Oceano Antartico", "Southern Ocean", "Océano Antártico" ], [ [ 60, -62 ], [ -60, -62 ], [ 150, -62 ] ] ]
    }.freeze

    # The twenty regions of Italy: Natural Earth's English spelling to ours.
    ITALY_REGIONS = {
      "Abruzzo" => "Abruzzo", "Apulia" => "Puglia", "Basilicata" => "Basilicata", "Calabria" => "Calabria",
      "Campania" => "Campania", "Emilia-Romagna" => "Emilia-Romagna", "Friuli-Venezia Giulia" => "Friuli-Venezia Giulia",
      "Lazio" => "Lazio", "Liguria" => "Liguria", "Lombardia" => "Lombardia", "Marche" => "Marche", "Molise" => "Molise",
      "Piemonte" => "Piemonte", "Sardegna" => "Sardegna", "Sicily" => "Sicilia", "Toscana" => "Toscana",
      "Trentino-Alto Adige" => "Trentino-Alto Adige", "Umbria" => "Umbria", "Valle d'Aosta" => "Valle d'Aosta", "Veneto" => "Veneto"
    }.freeze

    RIVER_MAX_RANK = 4
    HISTORIC_RIVERS = %w[Nile Danube Rhine Euphrates Tigris Rhône Po Tiber Ebro Tagus Guadalquivir Loire Seine Elbe Jordan Dnieper Don].freeze

    module_function

    def slug(text)
      text.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
    end

    # The id of a country in the gazetteer: ISO alpha-3 where Natural Earth has one that is unique,
    # else its own three-letter code (a territory); Kosovo is XKX as in common use.
    def country_id(props)
      return "XKX" if props["ADM0_A3"] == "KOS"
      iso = props["ISO_A3_EH"]
      iso && iso != "-99" && iso == props["ADM0_A3"] ? iso : props["ADM0_A3"].then { |a| ISO_FIX.fetch(a, a) }
    end

    ISO_FIX = { "SDS" => "SSD", "PSX" => "PSE", "SAH" => "ESH", "ALD" => "ALA" }.freeze

    # [features] of the 50m countries (the superset), skipping the glacier Natural Earth keeps apart.
    def countries(file = "ne_50m_admin_0_countries")
      Sources.read_checked(file)["features"].reject { |f| f["p"]["ADM0_A3"] == "KAS" }
    end

    def build_names
      overrides = YAML.safe_load_file(OVERRIDES).fetch("overrides")
      entries = {}
      add = lambda do |id, kind, it, en, es, source|
        ov = overrides[id]
        entries[id] = { "kind" => kind, "name_it" => ov ? ov["name_it"] : it, "name_en" => en, "name_es" => es,
                        "source" => ov ? "override (see names_overrides.yml)" : source }.compact
      end
      countries.each do |f|
        p = f["p"]
        kind = p["TYPE"] == "Sovereign country" || p["TYPE"] == "Country" ? "country" : "territory"
        add.call(country_id(p), kind, p["NAME_IT"], p["NAME_EN"], p["NAME_ES"], "Natural Earth admin-0 NAME_IT (Wikidata labels)")
      end
      CONTINENTS.each { |id, (it, en, es)| add.call(id, "continent", it, en, es, "ours (school usage)") }
      OCEANS.each { |id, ((it, en, es), _)| add.call(id, "ocean", it, en, es, "ours (school usage)") }
      ITALY_REGIONS.each_value { |it| add.call(slug(it), "region", it, nil, nil, "ours (the twenty regions)") }
      Sources.read_checked("ne_110m_populated_places")["features"].each do |f|
        p = f["p"]
        id = slug(p["NAMEASCII"])
        id = "#{id}-#{p['ADM0_A3'].downcase}" if entries.key?(id)
        add.call(id, "city", p["NAME_IT"], p["NAME_EN"], p["NAME_ES"], "Natural Earth populated places NAME_IT")
      end
      # the rivers the bases can draw: the ranks the bases use, and the rivers of the ancient base
      { "river" => [ %w[ne_110m_rivers_lake_centerlines ne_50m_rivers_lake_centerlines], RIVER_MAX_RANK ] }.each do |kind, (files, max_rank)|
        files.each do |file|
          Sources.read_checked(file)["features"].each do |f|
            p = f["p"]
            name = p["name_en"] || p["name"] or next
            next if p["scalerank"].to_i > max_rank && !(kind == "river" && HISTORIC_RIVERS.include?(name))
            id = slug(name)
            next if entries.key?(id)
            add.call(id, kind, p["name_it"] || p["name"], p["name_en"], p["name_es"], "Natural Earth #{kind}s name_it")
          end
        end
      end
      { "version" => 2, "generated_by" => "bin/build-maps --fetch", "names" => entries.sort_by { |id, e| [ e["kind"], id ] }.to_h }
    end

    def build_countries
      area = Sources.read_checked("worldbank_area_2021")
      pop = Sources.read_checked("worldbank_population_2023")
      out = {}
      countries.each do |f|
        p = f["p"]
        id = country_id(p)
        row = {}
        if (a = area["values"][id])
          row.merge!("area_km2" => a.round, "area_year" => area["year"], "area_source" => "World Bank WDI AG.SRF.TOTL.K2 (FAO), CC BY 4.0")
        end
        if (n = pop["values"][id])
          row.merge!("population" => n.round, "population_year" => pop["year"], "population_source" => "World Bank WDI SP.POP.TOTL, CC BY 4.0")
        elsif p["POP_EST"] && p["POP_EST"].positive?
          row.merge!("population" => p["POP_EST"].round, "population_year" => p["POP_YEAR"], "population_source" => "Natural Earth POP_EST (estimate)")
        end
        out[id] = row unless out.key?(id)
      end
      { "version" => 2, "generated_by" => "bin/build-maps --fetch", "countries" => out.sort.to_h }
    end

    def write!
      File.write(NAMES, YAML.dump(build_names))
      File.write(COUNTRIES, YAML.dump(build_countries))
    end
  end
end
