# frozen_string_literal: true

require "digest"
require "json"

module Validation
  # Canonical JSON (sorted keys, no spaces): the form a fingerprint is taken on.
  module Canonical
    module_function

    def dump(value)
      case value
      when Hash then "{#{value.sort_by { |k, _| k.to_s }.map { |k, v| "#{JSON.generate(k.to_s)}:#{dump(v)}" }.join(',')}}"
      when Array then "[#{value.map { |v| dump(v) }.join(',')}]"
      else JSON.generate(value)
      end
    end

    # sha256 of the canonical display: what "the same question" means.
    def fingerprint(display) = Digest::SHA256.hexdigest(dump(display))

    # Every String value (not key) of a nested structure, with its path.
    def strings(node, path = "", out = [])
      case node
      when String then out << [ path, node ]
      when Hash then node.each { |k, v| strings(v, "#{path}/#{k}", out) }
      when Array then node.each_with_index { |v, i| strings(v, "#{path}/#{i}", out) }
      end
      out
    end
  end
end
