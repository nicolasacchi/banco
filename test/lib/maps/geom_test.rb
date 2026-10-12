require "test_helper"

# The plane geometry under bin/build-maps: projections, clipping, simplification, dissolving, paths.
class MapsGeomTest < ActiveSupport::TestCase
  G = Maps::Geom

  test "Equal Earth puts the origin at 0,0 and the equator's end at the published value" do
    assert_equal [ 0.0, 0.0 ], G.equal_earth(0, 0).map { |v| v.abs < 1e-12 ? 0.0 : v }
    x, y = G.equal_earth(180, 0)
    assert_in_delta 2.7, x, 0.05 # the whole equator is about 5.4 wide in the unit of the formula
    assert_in_delta 0.0, y, 1e-9
    _, pole = G.equal_earth(0, 90)
    assert_in_delta 1.31, pole, 0.02
  end

  test "Equal Earth is odd in both coordinates" do
    a = G.equal_earth(40, 30)
    b = G.equal_earth(-40, -30)
    assert_in_delta a[0], -b[0], 1e-12
    assert_in_delta a[1], -b[1], 1e-12
  end

  test "the azimuthal projections put the pole in the centre and the 0 degree meridian down in the north, up in the south" do
    assert_equal [ 0.0, 0.0 ], G.azimuthal(77, 90, :north).map { |v| v.abs < 1e-12 ? 0.0 : v }
    x, y = G.azimuthal(0, 60, :north)
    assert_in_delta 0, x, 1e-12
    assert_operator y, :<, 0
    x, y = G.azimuthal(90, 60, :north)
    assert_operator x, :>, 0
    assert_in_delta 0, y, 1e-9
    _, ys = G.azimuthal(0, -60, :south)
    assert_operator ys, :>, 0
  end

  test "equal-area: a degree box has the same area at 0 and at 60 north in Equal Earth to within the formula's rounding" do
    box = lambda do |lat|
      pts = [ [ 0, lat ], [ 1, lat ], [ 1, lat + 1 ], [ 0, lat + 1 ] ].map { |lo, la| G.equal_earth(lo, la) }
      G.area(pts)
    end
    sphere = ->(lat) { Math.cos(G.rad(lat + 0.5)) }
    assert_in_delta box.call(0) / box.call(60), sphere.call(0) / sphere.call(60), 0.03
  end

  test "Mercator has straight meridians and the textbook stretch" do
    assert_in_delta G.raw_project("mercator", 10, 0)[0], G.raw_project("mercator", 10, 50)[0], 1e-12
    assert_in_delta Math.log(Math.tan(Math::PI / 4 + G.rad(45) / 2)), G.raw_project("mercator", 0, 45)[1], 1e-12
  end

  test "a fitted projection with crop is the largest upright rectangle inside the window, and its corners are inside the window" do
    pr = G.fit("equal_earth", [ 10, 30, 40, 60 ], 1000, crop: true)
    assert_in_delta 1000, pr.width, 1e-9
    pr.rect.then do |x0, y0, x1, y1|
      assert_in_delta 0, x0
      assert_in_delta 1000, x1
      assert_in_delta 0, y0
      assert_in_delta pr.height, y1
    end
    # the left edge of the window at the equator-most row touches the rectangle
    assert_in_delta 0.0, [ pr.project(10, 60)[0], pr.project(10, 30)[0] ].max, 1e-6
  end

  test "clip_ring keeps the part of a square inside a window" do
    ring = [ [ -10, -10 ], [ 10, -10 ], [ 10, 10 ], [ -10, 10 ] ]
    out = G.clip_ring(ring, [ 0, 0, 20, 20 ])
    assert_in_delta 100.0, G.area(out), 1e-9
    assert_empty G.clip_ring(ring, [ 50, 50, 60, 60 ])
  end

  test "clip_line splits a line that leaves and enters the window" do
    pieces = G.clip_line([ [ -5, 5 ], [ 15, 5 ], [ 15, 8 ], [ -5, 8 ] ], [ 0, 0, 10, 10 ])
    assert_equal 2, pieces.size
    assert_equal [ [ 0.0, 5.0 ], [ 10.0, 5.0 ] ], pieces[0]
    assert_equal [ [ 10.0, 8.0 ], [ 0.0, 8.0 ] ], pieces[1]
  end

  test "densify leaves no edge longer than the step" do
    ring = G.densify([ [ 0, 0 ], [ 10, 0 ], [ 10, 1 ] ], 2.0)
    ring.each_with_index { |p, i| q = ring[(i + 1) % ring.size]; assert_operator [ (q[0] - p[0]).abs, (q[1] - p[1]).abs ].max, :<=, 2.0 + 1e-9 }
  end

  test "simplify keeps the corners of a square with noisy sides and drops points within the tolerance" do
    ring = [ [ 0, 0 ], [ 5, 0.05 ], [ 10, 0 ], [ 10, 5 ], [ 10, 10 ], [ 5, 10.05 ], [ 0, 10 ], [ 0, 5 ] ]
    out = G.simplify(ring, 0.5)
    assert_equal [ [ 0, 0 ], [ 10, 0 ], [ 10, 10 ], [ 0, 10 ] ].sort, out.sort
    assert_equal [ [ 0, 0 ], [ 5, 0.05 ], [ 10, 0 ], [ 10, 10 ], [ 5, 10.05 ], [ 0, 10 ] ], G.simplify(ring, 0.0) # only the collinear points go
  end

  test "dissolve joins two squares that share an edge into one ring of six corners" do
    a = G.orient([ [ 0, 0 ], [ 1, 0 ], [ 1, 1 ], [ 0, 1 ] ], true)
    b = G.orient([ [ 1, 0 ], [ 2, 0 ], [ 2, 1 ], [ 1, 1 ] ], true)
    out = G.dissolve([ a, b ])
    assert_equal 1, out.size
    assert_in_delta 2.0, G.area(out.first), 1e-9
    assert_equal 6, out.first.size
  end

  test "dissolve leaves apart two squares that only touch at a corner" do
    a = G.orient([ [ 0, 0 ], [ 1, 0 ], [ 1, 1 ], [ 0, 1 ] ], true)
    b = G.orient([ [ 1, 1 ], [ 2, 1 ], [ 2, 2 ], [ 1, 2 ] ], true)
    assert_equal 2, G.dissolve([ a, b ]).size
  end

  test "anchor of a C shape lies inside it" do
    c = [ [ 0, 0 ], [ 10, 0 ], [ 10, 2 ], [ 2, 2 ], [ 2, 8 ], [ 10, 8 ], [ 10, 10 ], [ 0, 10 ] ]
    assert G.inside?(c, G.anchor(c))
  end

  test "numbers are written in tenths, shortest form, and paths accumulate no rounding" do
    assert_equal [ "12.3", "0", ".5", "-.5", "-4", "100" ], [ 12.34, -0.04, 0.5, -0.5, -4.0, 100.0 ].map { |v| G.num(v) }
    d = G.path([ [ [ 0.04, 0.04 ], [ 10.06, 0.0 ], [ 10.06, 5.0 ] ] ])
    assert_equal "M0 0l10.1 0 0 5z", d
  end
end
