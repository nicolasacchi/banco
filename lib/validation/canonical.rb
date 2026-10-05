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

    # The columns the server reshuffles at serve time (Diagnosis::Rekey).
    SHUFFLED = %w[options elements left right].freeze

    # sha256 of the canonical display: what "the same question" means. The shuffled
    # columns are taken without their ids and in a fixed order, so the stored order
    # and the ids authors chose do not make two displays "different" (D-089).
    def fingerprint(display) = Digest::SHA256.hexdigest(dump(unshuffled(display)))

    def unshuffled(node)
      case node
      when Hash
        node.to_h do |k, v|
          if SHUFFLED.include?(k.to_s) && v.is_a?(Array) && v.all?(Hash)
            [ k, v.map { |e| unshuffled(e.reject { |ek, _| ek.to_s == "id" }) }.sort_by { |e| dump(e) } ]
          else
            [ k, unshuffled(v) ]
          end
        end
      when Array then node.map { |v| unshuffled(v) }
      else node
      end
    end

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
