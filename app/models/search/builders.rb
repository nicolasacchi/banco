module Search
  # The documents of each group, built from the primary database. A builder's call returns [Search::Doc]; nothing else
  # touches the index. Which revisions are indexed (Builders::Live) is not who may see them: that is Search::Scope, at
  # query time.
  module Builders
    GROUPS = %w[lessons topics skills items references syllabus findings answers].freeze

    module_function

    def docs(group)
      raise ArgumentError, "unknown group #{group}" unless GROUPS.include?(group)

      const_get(group.camelize).call
    end
  end
end
