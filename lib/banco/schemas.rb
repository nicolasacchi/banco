# frozen_string_literal: true

require "json"
require "json_schemer"

module Banco
  # The frozen content formats (A-03, A-05, B-07, C-01): banco.skill_graph/1,
  # banco.item/1, banco.blueprint/1, banco.review/1, banco.solve/1, and the course formats
  # of Phase 1b (D-224..D-226): banco.lesson/1 (the parsed body; the lesson.md front matter is
  # $defs.front_matter; banco.lesson/2 in the same file, D-245), banco.course/1, banco.topic/1, banco.lesson_review/1. JSON Schemas
  # in config/banco/schemas/, validated with json_schemer in production too: the
  # E-SCHEMA check of every submission depends on it.
  #
  # A change to a schema after authoring has started means a new version
  # (banco.item/2) and a small migration for drafts; schema_version is in every
  # document.
  module Schemas
    NAMES = %w[skill_graph item blueprint review solve lesson course topic lesson_review diagram].freeze
    # banco.lesson/2 shares the lesson schema (a oneOf on its schema member, D-245).
    LESSON_FORMATS = %w[banco.lesson/1 banco.lesson/2].freeze
    URN = "urn:banco:schema:"
    SCHEMA_DIR = ->(root) { File.join(root, "config", "banco", "schemas") }
    FIXTURE_DIR = ->(root) { File.join(root, "test", "fixtures", "content") }

    Error = Struct.new(:code, :field, :message, keyword_init: true) do
      def to_h = { code: code, field: field, message: message }
    end

    class << self
      def root = defined?(Rails) ? Rails.root.to_s : File.expand_path("../..", __dir__)

      def schema(name)
        name = name.to_s
        raise ArgumentError, "unknown schema #{name}" unless NAMES.include?(name)

        @schemers ||= {}
        @schemers[name] ||= JSONSchemer.schema(read(name), ref_resolver: method(:resolve))
      end

      def read(name) = JSON.parse(File.read(File.join(SCHEMA_DIR.call(root), "#{name}.json")))

      # A schema may refer to another by "urn:banco:schema:NAME" (lesson.json to diagram.json).
      def resolve(uri)
        name = uri.to_s.delete_prefix(URN)
        raise ArgumentError, "unknown schema reference #{uri}" unless uri.to_s.start_with?(URN) && NAMES.include?(name)

        read(name)
      end

      # Format string of a schema name: "item" -> "banco.item/1".
      def format_of(name) = "banco.#{name}/1"

      def name_for(format)
        return "lesson" if LESSON_FORMATS.include?(format)

        NAMES.find { |n| format_of(n) == format }
      end

      # [] when the document is valid, otherwise E-SCHEMA errors with a JSON pointer.
      def validate(name, data)
        schema(name).validate(data).map do |e|
          Error.new(code: "E-SCHEMA", field: e["data_pointer"].to_s, message: e["error"].to_s)
        end
      end

      def valid?(name, data) = validate(name, data).empty?

      # The front matter of a lesson.md (a Hash from YAML.safe_load) against $defs.front_matter of
      # lesson.json (banco.lesson/1) or $defs.front_matter2 (banco.lesson/2, picked by its schema
      # member; anything else is checked as lesson/1); field pointers start with /front_matter.
      def validate_front_matter(data)
        def_name = data.is_a?(Hash) && data["schema"] == "banco.lesson/2" ? "front_matter2" : "front_matter"
        @front_matters ||= {}
        @front_matters[def_name] ||= begin
          whole = read("lesson")
          JSONSchemer.schema(whole.fetch("$defs").fetch(def_name).merge("$defs" => whole.fetch("$defs")), ref_resolver: method(:resolve))
        end
        @front_matters[def_name].validate(data).map do |e|
          Error.new(code: "E-SCHEMA", field: "/front_matter#{e['data_pointer']}", message: e["error"].to_s)
        end
      end

      # Same, picking the schema from the document's own "schema" member.
      def validate_document(data)
        name = data.is_a?(Hash) ? name_for(data["schema"]) : nil
        return [ Error.new(code: "E-SCHEMA", field: "/schema", message: "unknown or missing schema member") ] unless name

        validate(name, data)
      end

      def fixture_files(name, kind, dir: FIXTURE_DIR.call(root))
        Dir.glob(File.join(dir, name.to_s, kind.to_s, "*.json")).sort
      end

      # Production boot check: for every schema, the first good fixture is valid
      # and the first bad fixture is not. False when a schema has no pair.
      def validate_fixture_pair(dir: FIXTURE_DIR.call(root), names: NAMES)
        names.all? do |name|
          good = fixture_files(name, :good, dir: dir).first
          bad = fixture_files(name, :bad, dir: dir).first
          good && bad &&
            valid?(name, JSON.parse(File.read(good))) &&
            !valid?(name, JSON.parse(File.read(bad)))
        end
      end
    end
  end
end
