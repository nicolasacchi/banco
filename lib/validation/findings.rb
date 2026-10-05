# frozen_string_literal: true

require "yaml"

module Validation
  # One thing validation found. code is an E- or W- name of the registry
  # (config/banco/error_codes.yml); field points into the file; detail is small
  # structured data (a rule name, a seed, a count).
  Finding = Data.define(:code, :field, :message, :detail) do
    def severity = Codes.severity(code)
    def error? = severity == "error"
    def to_h = { code: code, severity: severity, field: field, message: message, detail: detail }.compact
  end

  # The registry's validation codes.
  module Codes
    REGISTRY = YAML.safe_load_file(File.expand_path("../../config/banco/error_codes.yml", __dir__), permitted_classes: [], aliases: false).freeze

    module_function

    def all = REGISTRY.fetch("validation")
    def known?(code) = all.key?(code)
    def severity(code) = all.fetch(code).fetch("severity")
    def stage(code) = all.fetch(code).fetch("stage")
  end

  # A list of findings that refuses codes the registry does not know (a typo here
  # would otherwise be a silent hole) and keeps one finding per code, field and
  # rule, counting repeats (a bad display on 24 seeds is one finding).
  class Findings
    include Enumerable

    def initialize
      @items = {}
    end

    def add(code, field, message, **detail)
      raise ArgumentError, "unknown validation code #{code}" unless Codes.known?(code)

      key = [ code, field, detail[:rule], detail[:skill] ]
      if (existing = @items[key])
        existing.detail[:count] = existing.detail.fetch(:count, 1) + 1
        existing.detail[:seeds] = ((existing.detail[:seeds] || []) + Array(detail[:seed])).first(5) if detail[:seed]
      else
        d = detail.dup
        seed = d.delete(:seed)
        d[:seeds] = [ seed ] if seed
        @items[key] = Finding.new(code: code, field: field.to_s, message: message.to_s, detail: d)
      end
      self
    end

    def merge!(other)
      other.each { |f| @items[[ f.code, f.field, f.detail[:rule], f.detail[:skill] ]] ||= f }
      self
    end

    def each(&) = @items.values.each(&)
    def errors = select(&:error?)
    def warnings = reject(&:error?)
    def codes = errors.map(&:code).uniq
    def any_error? = errors.any?
    def include_code?(code) = any? { |f| f.code == code }
    def size = @items.size
    def to_a = @items.values
  end
end
