# Shared by the tests of the wave 2 check components: sample checks and a fake figure type that offers select targets (no available
# figure type has any yet; each track adds its own).
module LessonChecksWave2World
  TILES = {
    "component" => "tiles", "prompt_it" => "Costruisci la frase.",
    "tiles" => [ { "id" => "a", "text_en" => "If" }, { "id" => "b", "text_en" => "it" }, { "id" => "c", "text_en" => "rains" }, { "id" => "d", "text_en" => "I" },
                 { "id" => "e", "text_en" => "will" }, { "id" => "f", "text_en" => "stay" }, { "id" => "g", "text_en" => "rained" } ],
    "answer" => %w[a b c d e f], "accept" => [ %w[d e f a b c] ],
    "errors" => [ { "answer" => %w[a b g d e f], "code" => "en_past_in_if", "message_it" => "Dopo if, qui serve il presente." } ]
  }.freeze

  ORDERING = {
    "component" => "ordering", "prompt_it" => "Metti in ordine.",
    "items" => [ { "id" => "p", "text_it" => "La proposta" }, { "id" => "q", "text_it" => "La discussione" }, { "id" => "r", "text_it" => "Il voto" }, { "id" => "s", "text_it" => "La firma" } ],
    "answer" => %w[p q r s], "errors" => [ { "answer" => %w[p r q s], "message_it" => "Prima si discute, poi si vota." } ]
  }.freeze

  module FakeFigure
    extend Lessons::Diagrams::Contract

    module_function

    def targets(data, set) = data.fetch("sets").fetch(set)

    def served(data, mode:) = { "type" => data["type"], "mode" => mode.to_s, "targets" => data["sets"]["nodes"].size }

    def target_names(_data, _set) = { "n2" => "nucleoide", "n4" => "ribosomi" }
  end

  def select_check(pick: "many", answer: %w[n2 n4], alt: "Una cellula con cinque parti.")
    { "component" => "select", "prompt_it" => "Tocca le parti.", "targets" => "nodes", "pick" => pick, "answer" => answer,
      "diagram" => { "type" => "network", "alt_it" => alt, "sets" => { "nodes" => %w[n1 n2 n3 n4 n5] } },
      "errors" => [ { "answer" => %w[n1], "code" => "bio_membrane", "message_it" => "Quella è la membrana." } ] }
  end
end
