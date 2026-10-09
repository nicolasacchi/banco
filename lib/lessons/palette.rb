# frozen_string_literal: true

require "yaml"

module Lessons
  # The colour roles, carriers and step tags of lessons (A6), read from config/banco/lesson_palette.yml.
  # `common` roles (highlight, correct, wrong, muted) belong to every subject; the others to one.
  module Palette
    PATH = File.expand_path("../../config/banco/lesson_palette.yml", __dir__)

    module_function

    def data = (@data ||= YAML.safe_load_file(PATH, permitted_classes: [], aliases: false).freeze)

    def version = data.fetch("version")

    # {name => definition} of the roles an author may name for +subject+.
    def roles(subject)
      subject_roles = data.dig(subject.to_s, "roles") || {}
      data.fetch("common").merge(subject_roles)
    end

    def role?(subject, name) = roles(subject).key?(name.to_s)

    def role(subject, name) = roles(subject)[name.to_s]

    # "glyph", "position", "icon" or "tint" for a role; nil when unknown.
    def carrier(subject, name) = role(subject, name)&.fetch("carrier", nil)

    def icon_role?(subject, name) = carrier(subject, name) == "icon"

    # The step tags (verbs) of a subject: {"develop" => {"label_it", "icon"}}.
    def step_tags(subject) = data.dig("step_tags", subject.to_s) || {}

    def step_tag?(subject, tag) = step_tags(subject).key?(tag.to_s)

    # The roles of +subject+'s own list (not common), for the legend and the diagrams.
    def subject_roles(subject) = data.dig(subject.to_s, "roles") || {}
  end
end
