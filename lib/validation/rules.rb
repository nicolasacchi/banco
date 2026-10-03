# frozen_string_literal: true

require "yaml"

module Validation
  # The thresholds of mechanical validation (A-06), read from
  # config/banco/validation_rules.yml. The file's version is stored with every
  # validation row.
  #
  #   Validation::Rules.get(:generator, :pool)          # => 24
  #   Validation::Rules.with(generator: { pool: 3 }) { ... }   # tests only
  module Rules
    PATH = File.expand_path("../../config/banco/validation_rules.yml", __dir__)

    class << self
      def data
        @data ||= YAML.safe_load_file(PATH, permitted_classes: [], aliases: false).freeze
      end

      def version = data.fetch("version")

      def get(*path)
        path.map(&:to_s).reduce(effective) { |node, key| node.fetch(key) }
      end

      def list(*path) = Array(get(*path))

      # Replaces values for the duration of the block (deep merge on the file's
      # tree). For tests; the file stays the one source in production.
      def with(overrides)
        saved = @override
        @override = deep_merge(saved || {}, stringify(overrides))
        yield
      ensure
        @override = saved
      end

      private

      def effective
        @override ? deep_merge(data, @override) : data
      end

      def deep_merge(a, b)
        a.merge(b) { |_k, x, y| x.is_a?(Hash) && y.is_a?(Hash) ? deep_merge(x, y) : y }
      end

      def stringify(value)
        case value
        when Hash then value.to_h { |k, v| [ k.to_s, stringify(v) ] }
        else value
        end
      end
    end
  end
end
