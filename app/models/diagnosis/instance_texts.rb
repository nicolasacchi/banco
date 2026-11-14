# frozen_string_literal: true

module Diagnosis
  # The texts of an instance display that the student reads, for Diagnosis::Overlap (D-297):
  # {strong: [...], weak: [...]}, normalized with the text grader's normalization, without
  # duplicates. Strong: the stem, the passage, the options, the elements and the left rows;
  # weak: the right column of a matching. A testlet takes those of its sub items.
  module InstanceTexts
    module_function

    def call(display)
      strong = []
      weak = []
      collect(display, strong, weak)
      strong = strong.reject(&:empty?).uniq
      { strong: strong.freeze, weak: (weak.reject(&:empty?).uniq - strong).freeze }.freeze
    end

    def collect(display, strong, weak)
      return unless display.is_a?(Hash)

      %w[stem_it passage_it].each { |k| strong << norm(display[k]) }
      %w[options elements left].each { |k| Array(display[k]).each { |e| strong << norm(e.is_a?(Hash) ? e["text"] : e) } }
      Array(display["right"]).each { |e| weak << norm(e.is_a?(Hash) ? e["text"] : e) }
      Array(display["sub_items"]).each { |s| collect(s.is_a?(Hash) ? s["display"] : nil, strong, weak) }
    end

    def norm(text) = text.is_a?(String) ? Grading::Closed::Text.normalize(text) : ""

    # The texts of a display, worked out on first use. Normalizing them is most of the time it takes to load a plan,
    # and only the choice between two instances of an item (Overlap) reads them: a page that only derives states never does.
    # Reads like the hash `call` returns.
    class Lazy
      def initialize(display)
        @display = display
      end

      def value = @value ||= InstanceTexts.call(@display)
      def [](key) = value[key]
      def to_h = value
      def ==(other) = other.respond_to?(:to_h) && value == other.to_h
      alias_method :eql?, :==
      def hash = value.hash
      def inspect = value.inspect
    end
  end
end
