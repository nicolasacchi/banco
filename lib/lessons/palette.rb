# frozen_string_literal: true

require "yaml"

module Lessons
  # The colour roles, carriers and step tags of lessons (A6), read from config/banco/lesson_palette.yml.
  # `common` roles (highlight, correct, wrong, muted) belong to every subject; the others to one. A role with `same_as:
  # SUBJECT.ROLE` (palette v2) takes that role's colours, carrier, icon and shape: same meaning, same colour across
  # subjects; it may keep its own label and question.
  module Palette
    PATH = File.expand_path("../../config/banco/lesson_palette.yml", __dir__)

    module_function

    def data = (@data ||= YAML.safe_load_file(PATH, permitted_classes: [], aliases: false).freeze)

    def version = data.fetch("version")

    # Names that are span kinds of the markup and never roles (markup v2).
    RESERVED_SPAN_KINDS = %w[en es it la code g].freeze

    # {name => definition} of the roles an author may name for +subject+ (same_as resolved).
    def roles(subject)
      data.fetch("common").merge(subject_roles(subject))
    end

    # The subjects with a palette, in the file's order.
    def subjects = data.keys - %w[version rules common step_tags]

    # The role a sentence centres on in this subject's lessons (italian predicate, english and spanish verb).
    def centre_role(subject) = data.dig(subject.to_s, "centre_role")

    # {home subject => [roles]}: the roles of a home palette this subject's pages draw (the palette test mixes them in).
    def embeds(subject) = data.dig(subject.to_s, "embeds") || {}

    # The definition a `same_as` role copies, with the role's own label and question; other roles as they are.
    def resolve(role)
      return role unless role["same_as"]

      owner_subject, owner_role = role["same_as"].split(".")
      data.fetch(owner_subject).fetch("roles").fetch(owner_role).merge(role.slice("label_it", "question_it"))
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
    def subject_roles(subject) = (data.dig(subject.to_s, "roles") || {}).transform_values { |r| resolve(r) }
  end
end
