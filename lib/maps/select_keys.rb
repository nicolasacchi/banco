# frozen_string_literal: true

require "json"
require "zlib"
require "securerandom"

module Maps
  # The opaque keys of the select plates (L3): public/vendor/banco-maps@1/select/<base>.js carries the geometry of a base with every
  # gazetteer id replaced by a key ("a14", "g3", "p20", "l2") drawn at random, once, and kept in lib/maps/select_keys.json. That file
  # is the server's: it is never under public/, never served. A select figure of a check is drawn from the plate and its `candidates`,
  # `places` and `lines` hold keys, so neither the page nor the base module it loads says which shape is which (the plan: place ids are
  # never in the page; L3: no ISO id).
  module SelectKeys
    FILE = File.expand_path("select_keys.json", __dir__)
    PREFIX = { "areas" => "a", "groups" => "g", "places" => "p", "lines" => "l" }.freeze

    module_function

    def read
      @read ||= File.exist?(FILE) ? JSON.parse(File.read(FILE)).freeze : { "seed" => 0, "bases" => {} }.freeze
    end

    def reset! = @read = nil

    # The key of an id of +base+ (ids are unique across areas, groups, places and lines of a base), or nil.
    def key(base, id) = read.dig("bases", base, id)

    def id(base, key)
      @reverse ||= {}
      (@reverse[base] ||= (read.dig("bases", base) || {}).invert)[key]
    end

    # The mapping for +docs+ ({ base => parsed base }) from the +existing+ one: a kept id keeps its key; a new id takes a free number
    # drawn from a shuffle seeded by the file's seed. Returns { "seed" =>, "bases" => { base => { id => key } } }, sorted.
    def assign(existing, docs)
      seed = existing["seed"].to_i.nonzero? || SecureRandom.random_number(1 << 62)
      bases = docs.sort.to_h do |base, doc|
        old = (existing.dig("bases", base) || {})
        map = {}
        PREFIX.each do |coll, pre|
          ids = Array(doc[coll]).map { |r| r["id"] }.sort
          kept = ids.select { |i| old[i]&.start_with?(pre) }
          used = kept.map { |i| old[i][1..].to_i }
          kept.each { |i| map[i] = old[i] }
          free = (1..(ids.size + used.max.to_i)).to_a - used
          free = free.shuffle(random: Random.new(Zlib.crc32("#{seed}:#{base}:#{coll}")))
          (ids - kept).each { |i| map[i] = "#{pre}#{free.shift}" }
        end
        [ base, map.sort_by { |_, k| [ k[0], k[1..].to_i ] }.to_h ]
      end
      { "seed" => seed, "bases" => bases }
    end

    def dump(mapping) = JSON.pretty_generate(mapping) + "\n"

    # The plate of a parsed base: the geometry with the keys, and nothing that names (reads, oceans, the tolerance).
    def plate(doc, map)
      k = ->(id) { map.fetch(id) }
      by_key = ->(rows) { rows.sort_by { |r| [ r["id"][0], r["id"][1..].to_i ] } }
      out = doc.slice("v", "base", "title_it", "fill_rule", "projection", "viewBox", "box", "crop", "detail", "approximate", "land")
      out["areas"] = by_key.call(doc["areas"].map { |a| a.merge("id" => k.call(a["id"])) })
      out["groups"] = by_key.call(doc["groups"].map { |g| g.merge("id" => k.call(g["id"]), "members" => g["members"].map { |m| k.call(m) }) }) if doc["groups"]
      out["water"] = doc["water"]
      out["lines"] = by_key.call(doc["lines"].map { |l| l.merge("id" => k.call(l["id"])) })
      out["places"] = by_key.call(doc["places"].map { |p| p.slice("x", "y").merge("id" => k.call(p["id"])) })
      out["graticule"] = doc["graticule"]
      out
    end
  end
end
