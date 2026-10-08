# frozen_string_literal: true

require "set"

module Practice
  # The topological order of the union graph of a subject (graph + course map), for Oggi (A8.8).
  # Kahn's algorithm, ties by key. Prerequisites outside the given skills are ignored (other subjects).
  module GraphOrder
    module_function

    # skills: [{"key" =>, "prerequisites" => [keys]}] (string keys, as in the stored JSON).
    # Returns {key => position}. Keys on a cycle (validation refuses cycles) come last, by key.
    def call(skills)
      prereqs = skills.to_h { |s| [ s["key"], Array(s["prerequisites"]) ] }
      known = prereqs.keys.to_set
      pending = prereqs.transform_values { |p| p.select { |k| known.include?(k) }.to_set }
      order = []
      ready = pending.select { |_, p| p.empty? }.keys.sort
      until ready.empty?
        key = ready.shift
        order << key
        pending.delete(key)
        pending.each_value { |p| p.delete(key) }
        ready = (ready + pending.select { |k, p| p.empty? && !ready.include?(k) && !order.include?(k) }.keys).sort
      end
      order.concat(pending.keys.sort)
      order.each_with_index.to_h
    end
  end
end
