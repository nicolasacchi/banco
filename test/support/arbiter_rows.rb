# Rows for the third reviewer's tests (D-222): a finding on an item and arbiter sessions on the two allowed models.
module ArbiterRows
  FIRST_MODEL = "claude-opus-5-5".freeze
  SECOND_MODEL = "claude-haiku-4-5-20251001".freeze

  def arbiter_session(model = FIRST_MODEL, role: "arbiter")
    AgentSession.create!(label: "t", role: role, agent: "test", model: model)
  end

  def assess!(finding, verdict, session: arbiter_session, note: "Ho confrontato la chiave con il calcolo a mano.")
    FindingAssessment.create!(review_finding: finding, agent_session: session, verdict: verdict, note_it: note)
  end

  # Both opinions on a finding: [first, second].
  def assess_both!(finding, first, second = first)
    [ assess!(finding, first, session: arbiter_session(FIRST_MODEL)), assess!(finding, second, session: arbiter_session(SECOND_MODEL)) ]
  end
end
