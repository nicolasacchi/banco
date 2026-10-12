# frozen_string_literal: true

module Lessons
  # The server's side of a `select` check (WAVE2 2.11): which stored target ids the check's figure offers and in which reading
  # order. The browser draws the figure in mode "select" and names its targets t1..tN in the order the type's JS targets()
  # returns; the server names them in the order the type's Ruby targets() returns (the two are held equal by the type's vectors).
  # So the response of a select check is a list of tN, and only this module turns it back into stored ids.
  module SelectTargets
    module_function

    # The type's Ruby module for the check's figure, or nil.
    def module_of(check) = Diagrams.module_for(check.dig("diagram", "type"))

    # The stored ids of the set in reading order. Raises NotImplementedError when the type has no targets yet.
    def ids(check)
      mod = module_of(check) or return []
      raise NotImplementedError, "#{check.dig('diagram', 'type')} offers no select targets" unless mod.is_a?(Diagrams::Contract)

      Array(mod.targets(check["diagram"], check["targets"])).map(&:to_s)
    end

    # {"t1" => stored id, ...}; empty when the type offers no targets (every response is then unreadable).
    def id_map(check)
      ids(check).each_with_index.to_h { |id, i| [ "t#{i + 1}", id ] }
    rescue NotImplementedError
      {}
    end

    # Does the type declare this set in its schema (x-banco-targets)?
    def declared_sets(check)
      type = check.dig("diagram", "type")
      Diagrams.schema_def(type)["x-banco-targets"].to_a
    rescue KeyError
      []
    end

    # The names a teacher reads for stored ids ("nucleoide"): the type's optional target_names(data, set) -> {id => name}, else the id.
    def names(check, stored_ids)
      mod = module_of(check)
      table = mod.is_a?(Diagrams::Contract) && mod.respond_to?(:target_names) ? mod.target_names(check["diagram"], check["targets"]).to_h { |k, v| [ k.to_s, v ] } : {}
      stored_ids.map { |id| table[id.to_s] || id.to_s }
    rescue NotImplementedError
      stored_ids.map(&:to_s)
    end
  end
end
