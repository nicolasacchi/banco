# frozen_string_literal: true

require "zlib"
require_relative "sources"

module Maps
  # Reads the Pleiades gazetteer of ancient places (CC BY 3.0). history/places holds the values we
  # use, with the Pleiades id; `bin/build-maps --fetch` checks every row against the dump.
  module Pleiades
    module_function

    # {id => {"title" =>, "lat" =>, "lon" =>}} for the given Pleiades ids, from the CSV dump.
    def lookup(dump_path, ids)
      wanted = ids.to_set(&:to_s)
      found = {}
      Zlib::GzipReader.open(dump_path) do |gz|
        header = nil
        each_row(gz) do |row|
          header ||= row
          next if row.equal?(header)
          r = header.zip(row).to_h
          next unless wanted.include?(r["id"])
          found[r["id"].to_i] = { "title" => r["title"], "lat" => r["reprLat"].to_f.round(3), "lon" => r["reprLong"].to_f.round(3) }
        end
      end
      found
    end

    # Rows of an RFC 4180 CSV stream (quoted fields may hold commas, quotes and line breaks). The csv
    # gem is no longer a default gem, and this is all we need of it.
    def each_row(io)
      row = []
      field = +""
      quoted = false
      pending_quote = false
      io.each_char do |c|
        if quoted
          if pending_quote
            if c == '"'
              field << '"'
              pending_quote = false
              next
            end
            quoted = false
            pending_quote = false
          elsif c == '"'
            pending_quote = true
            next
          else
            field << c
            next
          end
        end
        case c
        when '"' then quoted = true
        when "," then row << field
                      field = +""
        when "\n"
          row << field
          yield row
          row = []
          field = +""
        when "\r" then nil
        else field << c
        end
      end
      return if row.empty? && field.empty?
      row << field
      yield row
    end

    # Problems between the table and the dump (empty when they agree).
    def verify(places, dump_path)
      dump = lookup(dump_path, places.values.map { |p| p["pleiades"] })
      places.flat_map do |id, p|
        d = dump[p["pleiades"]]
        next [ "#{id}: Pleiades #{p['pleiades']} is not in the dump" ] unless d
        issues = []
        issues << "#{id}: title #{p['pleiades_title'].inspect} but the dump has #{d['title'].inspect}" if d["title"] != p["pleiades_title"]
        issues << "#{id}: lat/lon #{p['lat']},#{p['lon']} but the dump has #{d['lat']},#{d['lon']}" if d["lat"] != p["lat"] || d["lon"] != p["lon"]
        issues
      end
    end
  end
end
