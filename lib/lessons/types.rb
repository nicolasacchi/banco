# frozen_string_literal: true

require "yaml"

module Lessons
  # The availability registry of lesson/2 (D-265), read from config/banco/lesson_types.yml: which diagram types,
  # blocks, check components and options authors may use now (`available`), which have a frozen schema but no module yet
  # (`reserved`, schema `final`), which are W2-2 drafts (`draft`) and which are only a name (`reserved`, schema `none`).
  # It replaces RELEASE and BUILT of Directives. A name that is not available is refused at submit (E-LESSON-BLOCK);
  # the reserved dry run (`allow_reserved`) lets the schema see it and the caller answers W-TYPE-RESERVED or W-TYPE-DRAFT.
  module Types
    PATH = File.expand_path("../../config/banco/lesson_types.yml", __dir__)
    KINDS = { diagram: "diagrams", block: "blocks", check: "checks" }.freeze
    STATUSES = %w[available reserved draft].freeze

    module_function

    def data = (@data ||= YAML.safe_load_file(PATH, permitted_classes: [], aliases: false).freeze)

    def version = data.fetch("version")

    # The entry of a diagram type, a block type or a check component; nil when the registry does not know the name.
    def entry(kind, name) = data.fetch(KINDS.fetch(kind))[name.to_s]

    def known?(kind, name) = !entry(kind, name).nil?

    # "available", "reserved" or "draft"; nil for an unknown name.
    def status(kind, name) = entry(kind, name)&.fetch("status")

    def available?(kind, name) = status(kind, name) == "available"

    # May the name be used? Always when available; in the reserved dry run also when reserved or draft.
    def usable?(kind, name, allow_reserved: false)
      st = status(kind, name)
      st == "available" || (allow_reserved && STATUSES.include?(st))
    end

    # Names with a given status, in the file's order.
    def names(kind, status: nil)
      data.fetch(KINDS.fetch(kind)).select { |_, e| status.nil? || e["status"] == status }.keys
    end

    # The home palette (a subject) of a diagram type, or nil.
    def home_palette(type) = entry(:diagram, type)&.fetch("home_palette", nil)

    # [[field, value, spec]] for each layout, view, kind, scale or option of +data+ (a diagram or block body, a state
    # included) that the registry holds back: +spec+ has the status, schema and batch. Plain names only; `present` as a
    # value means the field itself is new.
    def held_back_uses(kind, name, body)
      views = entry(kind, name)&.fetch("views", nil)
      return [] unless views.is_a?(Hash) && body.is_a?(Hash)

      scopes = [ body ] + Array(body["states"]).select { |s| s.is_a?(Hash) }
      views.flat_map do |field, values|
        values.filter_map do |value, spec|
          next if spec["status"] == "available"

          hit = scopes.any? do |scope|
            next false unless scope.key?(field)

            value == "present" || Array(scope[field]).map(&:to_s).include?(value)
          end
          [ field, value, spec ] if hit
        end
      end
    end

    # [[option name, spec]] for the options of a check body that are not available.
    def held_back_options(check)
      return [] unless check.is_a?(Hash)

      component = check["component"].to_s
      data.fetch("check_options").filter_map do |name, spec|
        next if spec["status"] == "available"
        next unless spec["applies_to"] == "all" || Array(spec["applies_to"]).include?(component)
        next unless check.key?(spec["field"])
        next if spec["value"] && check[spec["field"]].to_s != spec["value"]

        [ name, spec ]
      end
    end

    # A sentence for the agent: what is held back and why.
    def describe_hold(label, status, batch)
      state = status == "draft" ? "a draft schema, not frozen until its family's first look" : "reserved"
      "#{label} is not available yet (#{state}; batch #{batch})"
    end
  end
end
