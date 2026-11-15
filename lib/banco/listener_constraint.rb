# frozen_string_literal: true

module Banco
  # Routing constraint: a route group answers only on its own listener (or listeners, D-332: the teacher's GET pages
  # answer on web and view) and is a plain 404 everywhere else.
  class ListenerConstraint
    def initialize(*names)
      @names = names.map(&:to_sym)
    end

    def matches?(request)
      @names.include?(request.env[ListenerTag::TAG_KEY])
    end
  end
end
