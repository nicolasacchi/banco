require "test_helper"

# D-375, the process: a change that a student or a teacher can see adds an entry to config/banco/changelog.yml in the same commit. A change shows up as
# a decision of docs/decisions.md, so from D-375 on a decision whose index row says it changes the student's pages (the words «student's pages», «student's
# menu», «student's screen», «student's interface» or «student's view») has to be named by an entry's `decisions:`. A decision that mentions those words
# and changes nothing he can see is written down in EXEMPT with the reason, in git, where the next reader finds it.
#
# It is a rule on the index row's words, so it catches a decision that says what it is about, not one that hides it: the AGENTS.md bullet is the rule,
# this test is the reminder.
class ChangelogProcessTest < ActiveSupport::TestCase
  FIRST = 375
  STUDENT_PAGES = /\bstudent(?:'s)? (?:pages?|menu|screens?|interface|view)\b/i

  # decision number => why no entry is needed (the decision does not change what he or the teacher can see)
  EXEMPT = {}.freeze

  def number(row) = row[:number].delete_prefix("D-").to_i

  # The decisions of the index (from FIRST on) that mention the student's pages and that no entry names and EXEMPT does not excuse.
  def unnamed(rows, entries, exempt: EXEMPT)
    named = entries.flat_map(&:decisions)
    rows.select { |row| number(row) >= FIRST && row[:title].match?(STUDENT_PAGES) && !named.include?(row[:number]) && !exempt.key?(number(row)) }.map { |row| row[:number] }
  end

  def entry(decisions) = Changelog::Entries::Entry.new(id: "x-entry", date: Date.new(2026, 11, 19), audience: [ "student" ], kind: "software", title_it: "A", body_it: "B.",
                                                       title_en: "A", body_en: "B.", decisions: decisions, topics: [], link: nil)

  test "every decision from D-375 on that mentions the student's pages is named by a changelog entry" do
    missing = unnamed(Updates.changes, Changelog::Entries.all)
    assert_empty missing, "#{missing.join(', ')}: its index row mentions the student's pages. Add an entry to config/banco/changelog.yml with decisions: [#{missing.first}] " \
                          "(title_it, body_it and, for the student, title_en and body_en), or write the decision in EXEMPT of this test with the reason."
  end

  test "the rule fails for a decision that says it changes the student's pages and has no entry, and passes once an entry names it or it is excused" do
    rows = [ { number: "D-374", title: "a change to the student's pages" }, { number: "D-376", title: "the student's pages get a new menu entry" },
             { number: "D-377", title: "the teacher's tools only" }, { number: "D-378", title: "a student view that nobody asked for" },
             { number: "D-379", title: "what the Student's Menu says" } ]
    assert_equal %w[D-376 D-378 D-379], unnamed(rows, [])
    assert_equal %w[D-378 D-379], unnamed(rows, [ entry([ "D-376" ]) ])
    assert_equal %w[D-379], unnamed(rows, [ entry([ "D-376", "D-378" ]) ])
    assert_empty unnamed(rows, [ entry([ "D-376" ]) ], exempt: { 378 => "a rule, nothing visible", 379 => "a word in a title" })
  end

  test "the exemptions are real decisions with a reason" do
    numbers = Updates.changes.map { |row| number(row) }
    assert_kind_of Hash, EXEMPT
    EXEMPT.each do |n, reason|
      assert_includes numbers, n, "D-#{n} is not in the index"
      assert_operator n, :>=, FIRST
      assert reason.to_s.length > 10, "D-#{n} needs a reason"
    end
  end

  test "this decision is named by its own entry" do
    assert_includes Updates.changes.map { |row| row[:number] }, "D-375"
    assert Changelog::Entries.all.any? { |e| e.decisions.include?("D-375") }, "D-375 has no entry"
  end
end
