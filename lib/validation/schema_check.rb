# frozen_string_literal: true

module Validation
  # JSON Schema validation (E-SCHEMA) with the few errors that have a code of
  # their own taken out and renamed:
  #
  # - the size of a choice, ordering or matching display is E-CHOICE-OPTIONS or
  #   E-MATCHING-SIZE, which InstanceChecks raises by looking at the instance;
  # - the number of entries of a blueprint is E-BLUEPRINT-ENTRIES.
  module SchemaCheck
    SIZE_FIELDS = %r{/display/(options|elements|left|right)\z}
    MAX_REPORTED = 12

    module_function

    # Adds E-SCHEMA findings for +data+ against banco.<name>/1; returns true when valid.
    def call(name, data, findings, prefix: "", skip_extra_in_display: false)
      added = 0
      ok = true
      Banco::Schemas.schema(name).validate(data).each do |e|
        pointer = e["data_pointer"].to_s
        type = e["type"]
        next if %w[minItems maxItems].include?(type) && pointer.match?(SIZE_FIELDS)
        # A key that reveals the answer is E-DISPLAY-KEY (InstanceChecks), not also an extra member.
        next if skip_extra_in_display && e["error"].to_s.include?("additional property") && pointer.match?(%r{/display(/|\z)})

        if name == "blueprint" && pointer == "/entries" && %w[minItems maxItems].include?(type)
          findings.add("E-BLUEPRINT-ENTRIES", "#{prefix}#{pointer}", "a blueprint has 4 to 10 starting skills", count: data["entries"]&.size)
          ok = false
        else
          findings.add("E-SCHEMA", "#{prefix}#{pointer}", message(e), rule: type) if (added += 1) <= MAX_REPORTED
          ok = false
        end
      end
      ok
    end

    # The library's wording, with a plainer one where it is cryptic: a constant
    # says what it must be, a string says it wants a string ("revision": "379").
    def message(error)
      pointer = error["data_pointer"].to_s
      case error["type"]
      when "const"
        "#{pointer} must be exactly #{error.dig('schema', 'const').to_json}, not #{error['data'].to_json}"
      when "string"
        "#{pointer} must be a string (in quotes), not #{error['data'].to_json}"
      else
        error["error"].to_s
      end
    end

    # Errors of a generated instance against the instance definition of banco.item/1
    # (E-GEN-SCHEMA), without the size rules left to InstanceChecks.
    def generated(output, findings, seed:)
      Banco::Schemas.schema("item").ref("#/$defs/instance").validate(output).each do |e|
        pointer = e["data_pointer"].to_s
        next if %w[minItems maxItems].include?(e["type"]) && pointer.match?(SIZE_FIELDS)

        findings.add("E-GEN-SCHEMA", "generated#{pointer}", e["error"].to_s, rule: e["type"], seed: seed)
      end
    end
  end
end
