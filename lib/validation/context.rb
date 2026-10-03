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
  #   source_line:     ->(source_key, number) { {text:, origin:} | nil }
  #   reference_body:  ->(key) { text of an imported reference text | nil }
  class Context
    attr_reader :subject

    def initialize(subject:, skill: ->(_k) { nil }, graph_present: true, source_line: ->(_s, _n) { nil }, reference_body: ->(_k) { nil },
                   approved_skill: ->(_k) { nil })
      @subject = subject
      @skill = skill
      @approved_skill = approved_skill
      @graph_present = graph_present
      @source_line = source_line
      @reference_body = reference_body
    end

    def skill(key) = @skill.call(key)
    def approved_skill(key) = @approved_skill.call(key)
    def graph_present? = @graph_present
    def source_line(source, number) = @source_line.call(source, number)
    def reference_body(key) = @reference_body.call(key)
  end
end
