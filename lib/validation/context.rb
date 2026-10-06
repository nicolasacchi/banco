# frozen_string_literal: true

module Validation
  # What validation needs to know about the course, as callables, so that the
  # checks themselves read no database:
  #
  #   skill:           ->(key) { skill hash of the subject's graph (or of an approved
  #                      graph of another subject) | nil }
  #   graph_present:   does the item's subject have a skill graph at all
  #   approved_skill:  ->(key) { skill hash from an APPROVED graph of another
  #                      subject | nil } (cross-subject edges and guest skills)
  #   draft_skill:     ->(key) { skill hash from the LATEST graph (approved or not) of
  #                      another subject | nil } (guest skills in drafts, D-129)
  #   source_line:     ->(source_key, number) { {text:, origin:} | nil }
  #   source_section:  ->(source_key, number) { the "## " heading the line sits under | nil }
  #   reference_body:  ->(key) { text of an imported reference text | nil }
  class Context
    attr_reader :subject

    def initialize(subject:, skill: ->(_k) { nil }, graph_present: true, source_line: ->(_s, _n) { nil }, reference_body: ->(_k) { nil },
                   approved_skill: ->(_k) { nil }, draft_skill: ->(_k) { nil }, source_section: ->(_s, _n) { nil })
      @subject = subject
      @skill = skill
      @approved_skill = approved_skill
      @draft_skill = draft_skill
      @graph_present = graph_present
      @source_line = source_line
      @reference_body = reference_body
      @source_section = source_section
    end

    def skill(key) = @skill.call(key)
    def approved_skill(key) = @approved_skill.call(key)
    def draft_skill(key) = @draft_skill.call(key)
    def graph_present? = @graph_present
    def source_line(source, number) = @source_line.call(source, number)
    def source_section(source, number) = @source_section.call(source, number)
    def reference_body(key) = @reference_body.call(key)
  end
end
