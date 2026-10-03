module Teacher
  # The teacher's words for what the software says in English (the reasons of the
  # approval gates, the decision refusals). Known sentences are turned into Italian;
  # an unknown one is shown as it is, so nothing is hidden by a missing rule.
  module Wording
    RULES = [
      [ /\Athe graph revision (\d+) of this test is not approved\z/, ->(_names, *) { "Prima approva il grafo su cui poggia questo test." } ],
      [ /\Aa reason is required\z/, ->(_names, *) { "Scrivi il motivo." } ],
      [ /\Aa comment is required\z/, ->(_names, *) { "Scrivi il commento." } ],
      [ /\Athe test pins no item\z/, ->(_names, *) { "Il test non contiene nessun item." } ],
      [ /\Athe test was not played to the end as the preview student\z/, ->(_names, *) { "Gioca il test fino in fondo con «Prova come S»." } ],
      [ /\Avalidation has not passed\z/, ->(_names, *) { "Il controllo meccanico non è passato." } ],
      [ /\Ano expert review on this revision\z/, ->(_names, *) { "Manca la revisione dell'esperto." } ],
      [ /\Ano blind solve on this revision\z/, ->(_names, *) { "Manca la prova alla cieca." } ],
      [ /\A(\d+) blocker or major finding\(s\) without the teacher's disposition\z/, ->(_names, n) { "#{n} rilievi gravi senza una tua decisione." } ],
      [ /\A(\d+) finding\(s\) the teacher asked to fix: a new revision is needed\z/, ->(_names, n) { "Hai chiesto una correzione (#{n}): serve una revisione nuova." } ],
      [ /\Athe teacher sent this revision back: a new revision is needed\z/, ->(_names, *) { "Hai rimandato questa revisione: serve una revisione nuova." } ],
      [ /\Aitem revision (\d+) was not opened in the preview\z/, ->(names, id) { "Apri la schermata dell'abilità dell'item #{label(id.to_i, names)}." } ],
      [ /\Aitem revision (\d+) does not exist\z/, ->(names, id) { "L'item #{label(id.to_i, names)} non esiste." } ]
    ].freeze

    module_function

    # reasons: English strings of a gate or a refusal. names: {revision id => item key}.
    def italian(reason, names = {})
      text = reason.to_s
      if (m = text.match(/\Aitem revision (\d+) is not approvable: (.*)\z/m))
        inner = m[2].split("; ").map { |r| italian(r, names) }.join(" ")
        return "#{label(m[1].to_i, names)}: #{inner}"
      end
      RULES.each do |pattern, make|
        m = text.match(pattern) or next
        return make.call(names, *m.captures)
      end
      text
    end

    def label(id, names) = names[id] || "revisione #{id}"
  end
end
