# frozen_string_literal: true

require "json"
require "yaml"

module Lessons
  # The vetted data tables of config/banco/data (W2-D08): `names` lists the tables that have a schema, `table(name)` reads one that has been
  # written (nil before), `valid?` checks it against its schema, `row` finds a row by id (what E-LESSON-DATA asks). Pure: no database.
  module VettedData
    DIR = File.expand_path("../../config/banco/data", __dir__)

    module_function

    # "chem/elements", ... : every table that has a schema.
    def names = Dir.glob("**/*.schema.json", base: DIR).map { |f| f.delete_suffix(".schema.json") }.sort

    def schema(name) = JSON.parse(File.read(File.join(DIR, "#{name}.schema.json")))

    # The track and use declared in the schema (x-banco-table).
    def meta(name) = schema(name).fetch("x-banco-table")

    def written?(name) = File.file?(File.join(DIR, "#{name}.yml"))

    # The table, or nil while it has not been written.
    def table(name)
      return nil unless written?(name)

      YAML.safe_load_file(File.join(DIR, "#{name}.yml"), permitted_classes: [], aliases: false)
    end

    # The E-SCHEMA style errors of a table against its schema ([] when it is valid).
    def errors(name, data = table(name))
      JSONSchemer.schema(schema(name)).validate(data).map { |e| "#{e['data_pointer']}: #{e['type']}" }
    end

    def valid?(name) = errors(name).empty?

    # The row +id+ of the collection +key+ of a table (a hash keyed by id, or an array of hashes with +id_field+); nil when absent.
    def row(name, key, id, id_field: "id")
      collection = table(name)&.dig(key)
      case collection
      when Hash then collection[id.to_s]
      when Array then collection.find { |r| r[id_field].to_s == id.to_s }
      end
    end
  end
end
