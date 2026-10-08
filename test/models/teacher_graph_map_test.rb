require "test_helper"
require_relative "../support/graph_map_rows"

# The layout of the skill map (D-221): pure Ruby, no database.
class TeacherGraphMapTest < ActiveSupport::TestCase
  S = Struct.new(:key, :label_it, :prerequisites, :composite_of, :deferred, keyword_init: true)

  setup { Teacher::GraphMap.reset_cache! }

  def skill(key, pre = [], label: key, composite: [], deferred: [])
    S.new(key: key, label_it: label, prerequisites: pre, composite_of: composite, deferred: deferred)
  end

  def big
    GraphMapRows::SKILLS.map do |suffix, (name, _scope, pre, _t, _n)|
      skill("math.#{suffix}", pre.map { |p| "math.#{p}" }, label: name, composite: Array(GraphMapRows::COMPOSITES[suffix]).map { |p| "math.#{p}" },
            deferred: suffix == "probability" ? [ { skill: "science.data", where: :prerequisite } ] : [])
    end
  end

  def seconda
    (1..13).map { |n| { id: "seconda:seconda-2026-27:#{n}", source: "seconda-2026-27", line: n, text: "Riga #{n} che richiede le basi", section: n.odd? ? "Algebra" : "Geometria", skills: [ "math.number", "math.lines" ] } }
  end

  def build(skills = big, **opts) = Teacher::GraphMap.call(skills: skills, revision_id: 1, **opts)

  def coords(map) = map.nodes.map { |n| [ n.key, n.x, n.y, n.w, n.h ] } + map.edges.map { |e| [ e.from, e.to, e.d ] }

  test "the same input gives the same coordinates, with or without the cache" do
    first = coords(build(stub_labels: { "science.data" => "Dati" }, seconda: seconda))
    Teacher::GraphMap.reset_cache!
    assert_equal first, coords(build(stub_labels: { "science.data" => "Dati" }, seconda: seconda))
    assert_equal first, coords(build(stub_labels: { "science.data" => "Dati" }, seconda: seconda)), "cached"
  end

  test "the order of the input skills does not change the picture" do
    assert_equal coords(build(big)).sort_by(&:inspect), coords(build(big.reverse)).sort_by(&:inspect)
  end

  test "no two boxes overlap" do
    map = build(stub_labels: { "science.data" => "Dati" }, seconda: seconda)
    boxes = map.nodes
    boxes.combination(2).each do |a, b|
      apart = a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y
      assert apart, "#{a.key} overlaps #{b.key}"
    end
    assert(boxes.all? { |n| n.x >= 0 && n.y >= 0 && n.x + n.w <= map.width && n.y + n.h <= map.height })
  end

  test "every prerequisite edge goes from a column to a column on its right" do
    map = build
    edges = big.flat_map { |s| (s.prerequisites + s.composite_of).uniq.map { |p| [ p, s.key ] } }
    assert_operator edges.size, :>, 30
    edges.each do |from, to|
      a = map.node(from)
      b = map.node(to)
      assert_operator a.x + a.w, :<, b.x, "#{from} -> #{to}"
      assert map.edges.any? { |e| e.from == from && e.to == to }, "edge #{from} -> #{to} is drawn"
    end
    assert_empty map.warnings
  end

  test "composite edges are their own kind and also go left to right" do
    map = build([ skill("p"), skill("q"), skill("whole", [ "p" ], composite: [ "p", "q" ]) ])
    assert_equal %i[composite prerequisite], map.edges.select { |e| e.to == "whole" }.map(&:kind).sort
    assert_operator map.node("q").x, :<, map.node("whole").x
  end

  test "labels are wrapped to three lines at most" do
    long = "Una etichetta molto lunga che continua e continua per molte parole senza fermarsi mai davvero, fino a superare le tre righe"
    lines = Teacher::GraphMap.wrap(long)
    assert_equal 3, lines.size
    assert_operator lines.map(&:length).max, :<=, Teacher::GraphMap::CHARS
    assert lines.last.end_with?("…")
    assert_equal [ "Frazioni" ], Teacher::GraphMap.wrap("Frazioni")
    assert_operator Teacher::GraphMap.wrap("Supercalifragilistichespiralidosissimo" * 2).map(&:length).max, :<=, Teacher::GraphMap::CHARS
  end

  test "a cycle is a warning and a dashed edge, never a crash" do
    map = build([ skill("a", [ "c" ]), skill("b", [ "a" ]), skill("c", [ "b" ]), skill("d", [ "c" ]) ])
    assert_equal [ :cycle ], map.warnings.map { |w| w[:kind] }.uniq
    assert_equal 4, map.nodes.size
    assert_equal 1, map.edges.count { |e| e.kind == :warning }
    assert_equal 4, map.edges.size
  end

  test "an unknown prerequisite and a self loop are warnings" do
    map = build([ skill("a", [ "a", "ghost" ]), skill("b", [ "a" ]) ])
    assert_equal %i[self_loop unknown_prerequisite], map.warnings.map { |w| w[:kind] }.sort
    assert_equal 1, map.edges.size
  end

  test "deferred prerequisites are stubs in a lane on the left" do
    map = build(stub_labels: { "science.data" => "Dati e grafici" })
    stub = map.nodes.find { |n| n.kind == :stub }
    assert_equal "science.data", stub.key
    assert_equal map.nodes.map(&:x).min, stub.x
    assert map.lane
    assert map.edges.any? { |e| e.kind == :stub && e.from == "science.data" && e.to == "math.probability" }
    assert map.groups.any? { |g| g.label == "lane" }
  end

  test "without stubs there is no lane, and the second year adds a right-most column" do
    plain = build(big.map { |s| skill(s.key, s.prerequisites, label: s.label_it) })
    assert_not plain.lane
    assert_equal plain.width, plain.main_width
    with = build(big.map { |s| skill(s.key, s.prerequisites, label: s.label_it) }, seconda: seconda)
    assert_operator with.width, :>, with.main_width
    rights = with.nodes.select { |n| n.kind == :seconda }
    assert_equal 13, rights.size
    assert(rights.all? { |n| n.x > with.nodes.select { |m| m.kind == :skill }.map { |m| m.x + m.w }.max })
    assert_equal 26, with.edges.count { |e| e.kind == :seconda }
    assert_equal %w[Algebra Geometria], with.groups.map(&:label).sort
  end

  test "an empty graph is an empty map" do
    map = build([])
    assert_empty map.nodes
    assert_empty map.edges
  end
end
