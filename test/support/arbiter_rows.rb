# Rows for the third reviewer's tests (D-222, D-316): a finding on an item and arbiter sessions. Only the first model
# (claude-opus-5-5) is allowed and counts since D-316; OLD_SECOND_MODEL is the second opinion model of the past: its
# assessments still exist in the ledger as history, and a test makes them by creating the session directly.
module ArbiterRows
  FIRST_MODEL = "claude-opus-5-5".freeze
  OLD_SECOND_MODEL = "claude-haiku-4-5-20251001".freeze

  def arbiter_session(model = FIRST_MODEL, role: "arbiter")
    AgentSession.create!(label: "t", role: role, agent: "test", model: model)
  end

  def assess!(finding, verdict, session: arbiter_session, note: "Ho confrontato la chiave con il calcolo a mano.")
    FindingAssessment.create!(review_finding: finding, agent_session: session, verdict: verdict, note_it: note)
  end

  # The opinion on a finding, and (as before D-316) an old second opinion that is history only: [first, old_second].
  def assess_with_old_second!(finding, first, second = first)
    [ assess!(finding, first, session: arbiter_session(FIRST_MODEL)), assess!(finding, second, session: arbiter_session(OLD_SECOND_MODEL)) ]
  end
end
