# config/banco/providers.yml: which model family a session belongs to and which
# families a role may use (A-08, operator Q8). The model is declared by the session.
module Providers
  CONFIG = Rails.root.join("config/banco/providers.yml")

  module_function

  def config = (@config ||= YAML.safe_load_file(CONFIG))

  # For tests that point the rules elsewhere.
  def reset! = (@config = nil)

  # "anthropic", "openai", ... or "unknown".
  def family(model)
    name = model.to_s.strip.downcase
    return "unknown" if name.empty?

    config.fetch("families").each do |family, patterns|
      return family if Array(patterns).any? { |p| File.fnmatch?(p.downcase, name) }
    end
    "unknown"
  end

  # The model compared across sessions: case and a leading "provider/" ignored.
  def model_key(model) = model.to_s.strip.downcase.split("/").last.to_s

  def rule(role) = config.fetch("roles").fetch(role.to_s, {}) || {}

  def families = config.fetch("families").keys

  # The normalized model that gives the first (and, since D-316, the only) opinion.
  def first_opinion_model = model_key(rule("arbiter")["first_opinion_model"])

  # :first for the arbiter's model, nil for any other model. The second opinion was dropped (D-316): an old
  # assessment of the second model has no slot and only shows as history.
  def opinion_slot(model) = model_key(model) == first_opinion_model ? :first : nil

  # Independence read at the time of reading (D-316), with the TRUE model of every session (AgentSession#model):
  # a session is independent of +authors+ (AgentSession rows) when none of them runs on its model. The write-time
  # refusal below is the same rule, applied once; this one is applied again each time a gate counts a review or a solve.
  def independent?(session, authors)
    mine = model_key(session.model)
    return true if mine.empty? # a session that declared no model (old rows, fixtures) is not held against anyone

    authors.none? { |a| model_key(a.model) == mine }
  end

  # The review or solve rows (ItemReview, BlindSolve, LessonReview, PageReview) that count, among +rows+ on +thing+
  # (an Item, a Lesson or a Page): the ones whose session is independent of every author of the thing.
  def counting(rows, thing)
    rows = rows.to_a
    return rows if rows.empty?

    authors = ItemSessions.for(thing).sessions("author")
    rows.select { |row| independent?(row.agent_session, authors) }
  end

  # True when the arbiter session runs on another model than the session that raised the finding (D-316: derived at read time).
  def different_from_raiser?(arbiter_session, raiser_session)
    raiser_session.nil? || model_key(raiser_session.model) != model_key(arbiter_session.model)
  end

  # nil when the session may act in its role on +item+ (nil: not item-specific),
  # otherwise the reason, in English, for E-PROVIDER-NOT-ALLOWED.
  def refusal(session, item: nil, finding: nil)
    rule = rule(session.role)
    family = session.family
    if rule["allow_families"] && !Array(rule["allow_families"]).include?(family)
      return "a #{session.role} session must run on #{Array(rule['allow_families']).join(' or ')}; this one declares #{session.model.inspect} (family #{family})"
    end
    return "the model #{session.model.inspect} is in no known family: add it to config/banco/providers.yml or use another model" if rule["known_family"] && family == "unknown"

    if rule["different_model_from"] && item
      authors = ItemSessions.for(item).sessions(rule["different_model_from"])
      mine = model_key(session.model)
      same = authors.find { |a| model_key(a.model) == mine }
      return "a #{session.role} must run on a different model than every author of the item: both are #{session.model.inspect}" if same
    end
    if rule["allow_models"] && !Array(rule["allow_models"]).any? { |p| File.fnmatch?(p.downcase, model_key(session.model)) }
      return "a #{session.role} session must run on one of #{Array(rule['allow_models']).join(', ')}; this one declares #{session.model.inspect}"
    end
    if rule["different_model_from_raiser"] && finding
      raiser = AgentSession.find_by(id: finding.raised_by_session_id)
      return "an arbiter must run on a different model than the session that raised the finding: both are #{session.model.inspect}" if raiser && model_key(raiser.model) == model_key(session.model)
    end
    nil
  end
end
