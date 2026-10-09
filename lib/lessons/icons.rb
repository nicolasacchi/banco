# frozen_string_literal: true

require "yaml"

module Lessons
  # The icons an author may name (A6): `structural` plus the list of the lesson's subject, from
  # config/banco/icons.yml. `ui` icons belong to our templates and are not the agent's.
  module Icons
    PATH = File.expand_path("../../config/banco/icons.yml", __dir__)
    # Default icon of a card by role (A3).
    ROLE_DEFAULTS = { "idea" => "lightbulb", "example" => "pencil-ruler", "mistakes" => "triangle-alert",
                      "try" => "notebook-pen", "summary" => "list-checks" }.freeze
    EXTRA_DEFAULT = "telescope"

    module_function

    def data = (@data ||= YAML.safe_load_file(PATH, permitted_classes: [], aliases: false).freeze)

    def names_for(subject)
      data.fetch("structural").keys + (data.dig("subjects", subject.to_s) || {}).keys
    end

    def allowed?(subject, name) = names_for(subject).include?(name.to_s)

    # Any icon of any list, for our own templates (role icons of a palette, callouts).
    def known?(name)
      n = name.to_s
      data.fetch("structural").key?(n) || data.fetch("ui").key?(n) || data.fetch("subjects").values.any? { |l| l.key?(n) }
    end

    def default_for(role, extra: false) = extra ? EXTRA_DEFAULT : ROLE_DEFAULTS.fetch(role.to_s, "lightbulb")
  end
end
