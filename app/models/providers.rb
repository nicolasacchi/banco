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

  def rule(role) = config.fetch("roles").fetch(role.to_s, {}) || {}

  def families = config.fetch("families").keys

  # nil when the session may act in its role on +item+ (nil: not item-specific),
  # otherwise the reason, in English, for E-PROVIDER-NOT-ALLOWED.
  def refusal(session, item: nil)
    rule = rule(session.role)
    family = session.family
    if rule["allow_families"] && !Array(rule["allow_families"]).include?(family)
      return "a #{session.role} session must run on #{Array(rule['allow_families']).join(' or ')}; this one declares #{session.model.inspect} (family #{family})"
    end
    return "the model #{session.model.inspect} is in no known family: add it to config/banco/providers.yml or use another model" if rule["known_family"] && family == "unknown"

    if rule["different_from"] && item
      authors = ItemSessions.new(item).sessions(rule["different_from"])
      same = authors.find { |a| a.family == family }
      return "a #{session.role} must be of another model family than the author: both are #{family}" if same
    end
    nil
  end
end
