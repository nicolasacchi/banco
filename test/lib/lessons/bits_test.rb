require "test_helper"

# Lessons::Bits against the shared vectors of the browser twin (test/fixtures/lesson2/bits.json; app/javascript/lesson/test/bits.test.mjs).
class LessonsBitsTest < ActiveSupport::TestCase
  VECTORS = JSON.parse(Rails.root.join("test/fixtures/lesson2/bits.json").read)

  def run_case(fn, args)
    b = Lessons::Bits
    case fn
    when "read" then b.read(args[0], base: (args[1] || 2).to_i, twos: args[2] == "true")
    when "write" then b.write(args[0], args[1].to_i, base: (args[2] || 2).to_i, twos: args[3] == "true")
    when "add" then b.add(args[0], args[1], args[2].to_i, base: (args[3] || 2).to_i)
    when "sub" then b.sub(args[0], args[1], args[2].to_i, base: (args[3] || 2).to_i)
    when "mul" then b.mul(args[0], args[1], args[2].to_i, base: (args[3] || 2).to_i)
    when "repeated_division" then b.repeated_division(args[0], args[1].to_i)
    else flunk "unknown function #{fn}"
    end
  end

  test "the signatures are those of the vector file" do
    assert_equal VECTORS["functions"].keys.sort, Lessons::Bits::SIGNATURES.keys.sort
    VECTORS["functions"].each { |name, spec| assert_equal spec["ruby"], Lessons::Bits::SIGNATURES[name], name }
  end

  test "every vector case gives its result (a refused call is {error: argument})" do
    VECTORS["functions"].each do |fn, spec|
      assert_operator spec["cases"].size, :>=, 4, "#{fn} has cases"
      spec["cases"].each do |c|
        got = begin
          run_case(fn, c["args"])
        rescue ArgumentError
          { "error" => "argument" }
        end
        want = c["result"]
        want = want.to_i if fn == "read" && want.is_a?(String)
        want.nil? ? assert_nil(got, "#{fn} #{c['args'].inspect}") : assert_equal(want, got, "#{fn} #{c['args'].inspect}")
      end
    end
  end

  test "write then read is the identity on every value of a register, and add is the sum modulo the register" do
    (-8..7).each { |v| assert_equal v, Lessons::Bits.read(Lessons::Bits.write(v, 4, twos: true), twos: true) }
    (0..15).each { |a| (0..15).each { |b| assert_equal (a + b) % 16, Lessons::Bits.read(Lessons::Bits.add(Lessons::Bits.write(a, 4), Lessons::Bits.write(b, 4), 4)["digits"]) } }
    (0..15).each { |a| (0..15).each { |b| assert_equal (a - b) % 16, Lessons::Bits.read(Lessons::Bits.sub(Lessons::Bits.write(a, 4), Lessons::Bits.write(b, 4), 4)["digits"]) } }
    (0..15).each { |a| (0..7).each { |b| assert_equal a * b, Lessons::Bits.read(Lessons::Bits.mul(Lessons::Bits.write(a, 4), Lessons::Bits.write(b, 3), 4)["full"]) } }
  end
end
