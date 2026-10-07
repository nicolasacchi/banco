# The disjoint-sessions rule for the reviewer and the blind solver (A-04, A-05):
# on one item the sessions of author, verifier, reviewer and solver are different,
# and a second round uses a session that did not see the first.
module IndependentRoles
  private

  # True when +session+ may act as +role+ (reviewer or solver) on +item+; otherwise
  # answers 422 E-SESSION-NOT-INDEPENDENT and returns false.
  def independent_role?(session, item, role)
    sessions = ItemSessions.new(item)
    held = sessions.conflicts(session.id, role)
    if held.any?
      refuse("E-SESSION-NOT-INDEPENDENT", "X-Banco-Session", "session #{session.id} already acted as #{held.join(' and ')} on #{item.key}: the #{role} must be another session",
             "banco session new --role #{role} --agent NAME --model MODEL", 422)
      return false
    end
    return true unless sessions.ids(role).include?(session.id)

    refuse("E-SESSION-NOT-INDEPENDENT", "X-Banco-Session", "session #{session.id} has already worked as #{role} on #{item.key}: a second round needs a session that did not see the first",
           "banco session new --role #{role} --agent NAME --model MODEL", 422)
    false
  end

  # The step's own open command on the latest revision (D-207: a superseded revision is not worked).
  def latest?(revision, item, step:)
    return true if revision.id == item.latest_revision.id

    refuse("E-STALE-BASE", "revision", "revision #{revision.id} is not the latest of #{item.key} (#{item.latest_revision.id})", "banco #{step} open #{item.latest_revision.id}", 409)
    false
  end

  def latest_and_passed?(revision, item, step: "solve")
    return false unless latest?(revision, item, step: step)
    return true if revision.status == "passed"

    refuse("E-ITEM-NOT-PASSED", "revision", "revision #{revision.id} has not passed validation (status #{revision.status})", "banco work status #{revision.id} --wait", 422)
    false
  end

  def brief_row(name)
    brief = Brief.find(name) or return nil
    { name: brief.name, version: brief.version, sha256: brief.sha256 }
  end
end
