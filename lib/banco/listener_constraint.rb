# frozen_string_literal: true

module Banco
  # Routing constraint: a route group answers only on its own listener and is a
  # plain 404 everywhere else.
  class ListenerConstraint
    def initialize(name)
      @name = name.to_sym
    end

    def matches?(request)
      request.env[ListenerTag::TAG_KEY] == @name
    end
  end
end
