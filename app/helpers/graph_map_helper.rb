# Small pieces of the skill map's markup (D-221). Classes only: the page's CSP-safe SVG has no style attributes.
module GraphMapHelper
  REPORT_STATES = %w[demonstrated to_recover to_learn pending not_assessed not_needed].freeze
  STATE_GLYPH = { "demonstrated" => "✓", "to_recover" => "↺", "to_learn" => "+", "pending" => "…", "not_assessed" => "–", "not_needed" => "·" }.freeze
  EVIDENCE_WORD = { "C" => "giusta", "W" => "sbagliata", "D" => "non lo so" }.freeze

  # The state a node shows in the report: the report's group, with "non serve" apart from "non valutata".
  def gm_state(row)
    return "not_assessed" unless row
    return "not_needed" if row[:reason] == "not_needed"

    row[:group]
  end

  def gm_node_title(skill, ctx, state: nil)
    parts = [ "#{skill.label_it} (#{skill.key})", scope_text(skill.scope) ]
    parts << t("teacher.graph.map.inferred_short") if skill.inferred
    parts << t("teacher.graph.map.pinned_short", count: ctx.pinned_count(skill.key)) if ctx.pinned_count(skill.key).positive?
    parts << t("teacher.graph.map.entry") if ctx.entry?(skill.key)
    parts << t("teacher.graph.map.change_short.#{skill.change}") if skill.change != :same
    parts << t("teacher.graph.map.state.#{state}") if state
    parts.join(". ")
  end

  def gm_dom_id(key) = "gm-#{key.to_s.parameterize}"

  def gm_text_lines(node)
    node.lines.each_with_index.map do |line, i|
      tag.tspan(line, x: node.x + 10, y: (node.y + 10 + 17 * (i + 1) - 5).round(1))
    end
  end
end
