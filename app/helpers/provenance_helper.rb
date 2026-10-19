# How the teacher's pages show who filed a review or a solve and on which model (D-316). The model is the TRUE one
# (AgentSession#model); a correction of the operator shows next to the declared model, and a review by a session on
# the same model as an author is marked «non indipendente» (it does not count for any gate).
module ProvenanceHelper
  # "claude-opus-5-5", or "claude-opus-5-5 (dichiarato: claude-sonnet-5-5, corretto dall'operatore: reason)".
  def session_model_text(session)
    return session.model.to_s unless session.corrected?

    t("teacher.provenance.corrected", model: session.model, declared: session.declared_model, reason: session.correction.reason)
  end

  # The pill «non indipendente», or nil when the row counts.
  def not_independent_pill(independent)
    independent ? nil : tag.span(t("teacher.provenance.not_independent"), class: "pill error", title: t("teacher.provenance.not_independent_hint"), "data-not-independent": "")
  end

  # One line for an item review or a blind solve: who, on which model, and whether it counts.
  def provenance_line(prov, what)
    return nil unless prov

    safe_join([ t("teacher.provenance.by", what: what, id: prov.session.id, model: session_model_text(prov.session)), " ", not_independent_pill(prov.independent) ].compact)
  end
end
