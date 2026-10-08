module Teacher
  # The teacher's words for what the software says in English (the reasons of the
  # approval gates, the decision refusals). Known sentences are turned into Italian;
  # an unknown one is shown as it is, so nothing is hidden by a missing rule.
  module Wording
    RULES = [
      [ /\Athe graph revision (\d+) of this test is not approved\z/, ->(_names, *) { "Prima approva il grafo su cui poggia questo test." } ],
      [ /\Aa reason is required\z/, ->(_names, *) { "Scrivi il motivo." } ],
      [ /\Aa comment is required\z/, ->(_names, *) { "Scrivi il commento." } ],
      [ /\Aenabled is true or false\z/, ->(_names, *) { "Scegli se accendere o spegnere il formulario." } ],
      [ /\Athe entry test of (\w+) has no formula sheet\z/, ->(_names, *) { "Questo test non ha un formulario da accendere." } ],
      [ /\Athe test pins no item\z/, ->(_names, *) { "Il test non contiene nessun item." } ],
      [ /\Athe test was not played to the end as the preview student, and not confirmed as seen in full\z/, ->(_names, *) { "Gioca il test fino in fondo con «Prova come S», oppure apri «Tutte le domande» e conferma di averle viste." } ],
      [ /\Avalidation has not passed\z/, ->(_names, *) { "Il controllo meccanico non è passato." } ],
      [ /\Ano expert review on this revision\z/, ->(_names, *) { "Manca la revisione dell'esperto." } ],
      [ /\Ano blind solve on this revision\z/, ->(_names, *) { "Manca la prova alla cieca." } ],
      [ /\A(\d+) blocker or major finding\(s\) without the teacher's disposition\z/, ->(_names, n) { "#{n} rilievi gravi senza una tua decisione." } ],
      [ /\A(\d+) finding\(s\) the teacher asked to fix: a new revision is needed\z/, ->(_names, n) { "Hai chiesto una correzione (#{n}): serve una revisione nuova." } ],
      [ /\Athe teacher sent this revision back: a new revision is needed\z/, ->(_names, *) { "Hai rimandato questa revisione: serve una revisione nuova." } ],
      [ /\Aitem revision (\d+) was not opened in the preview\z/, ->(names, id) { "Apri la schermata dell'abilità dell'item #{label(id.to_i, names)}." } ],
      [ /\Aitem revision (\d+) does not exist\z/, ->(names, id) { "L'item #{label(id.to_i, names)} non esiste." } ],
      [ /\Athe topic (\S+) is not in the latest course map of (\w+) with the same skills\z/, ->(_names, *) { "L'argomento non è più nella mappa del corso con le stesse abilità: serve una versione nuova dell'agente." } ],
      [ /\Athe pinned lesson revision (\d+) is not the newest revision of its lesson \((\d+)\)\z/, ->(_names, *) { "La lezione fissata non è l'ultima versione: serve un argomento nuovo." } ],
      [ /\Aitem revision (\d+) is no longer the newest passed revision of its item: (\d+) replaced it\z/, ->(names, id, _newer) { "L'item #{label(id.to_i, names)} ha una versione più nuova: serve un argomento nuovo." } ],
      [ /\Athe lesson revision has no review by an independent session\z/, ->(_names, *) { "La lezione non ha ancora la revisione di un altro agente." } ],
      [ /\Athe teacher sent the lesson revision back\z/, ->(_names, *) { "Hai rimandato questa lezione: serve una versione nuova." } ],
      [ /\Athe topic review page of revision (\d+) was not opened\z/, ->(_names, *) { "Apri la pagina dell'argomento e leggila." } ],
      [ /\Athe teacher did not confirm reading the lesson and the sample instances\z/, ->(_names, *) { "Conferma di aver letto la lezione e le istanze campione." } ],
      [ /\Aa reason is required to approve despite the blocker or major findings of the lesson review\z/, ->(_names, *) { "La revisione della lezione ha rilievi gravi: scrivi perché approvi lo stesso." } ],
      [ /\Atopic revision (\d+) is not the latest of (\S+): approve the latest\z/, ->(_names, *) { "Questa non è l'ultima versione dell'argomento: approva l'ultima." } ],
      [ /\Athe course map was not validated against the approved graph of (\w+)\z/, ->(_names, *) { "La mappa del corso non poggia sul grafo approvato." } ],
      [ /\Ano topic of the course map is approved\z/, ->(_names, *) { "Nessun argomento della mappa è approvato." } ],
      [ /\Athe course is already open with this map\z/, ->(_names, *) { "Il corso è già aperto con questa mappa." } ],
      [ /\Athe course of (\w+) is not open\z/, ->(_names, *) { "Il corso non è aperto." } ],
      [ /\Athere is no course map for (\w+)\z/, ->(_names, *) { "Non c'è ancora una mappa del corso." } ],
      [ /\Aopen is 1 or 0\z/, ->(_names, *) { "Scegli se aprire o chiudere il corso." } ]
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
