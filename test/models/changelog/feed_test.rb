require "test_helper"
require_relative "../../support/changelog_world"

# D-375, «Novità»: the content updates read from the ledger (an approve_topic that replaced an earlier approved revision), what the student sees of
# them (only his course's topics, never the teacher's reason), «Le tue segnalazioni», the merge of the three sources and the visits.
class ChangelogFeedTest < ActiveSupport::TestCase
  include ChangelogWorld

  CU = Changelog::ContentUpdates

  setup { build_student_world }

  def view(student = @official) = Course::StudentView.new(student)

  # ---- what the ledger says -------------------------------------------------------------------------------

  test "a first approval is no update; a second one that replaces it is, with both revisions and the title" do
    assert_empty CU.all
    second = travel_to(Time.zone.local(2026, 11, 20, 10, 0)) { revise! }
    update = CU.all.sole
    assert_equal [ @topic_key, @topic_revision.id, second.id, TOPIC_TITLE, "math" ], [ update.topic, update.old_revision_id, update.new_revision_id, update.title_it, update.subject_key ]
    assert_equal Date.new(2026, 11, 20), update.date
    assert_nil update.reason_it
    assert_equal "web", update.via
  end

  test "the same revision approved again replaces nothing; three revisions are two updates, newest first" do
    approve_topic!(@topic_revision)
    assert_empty CU.all
    second = travel_to(2.days.ago) { revise! }
    third = revise!
    updates = CU.all
    assert_equal [ [ second.id, third.id ], [ @topic_revision.id, second.id ] ], updates.map { |u| [ u.old_revision_id, u.new_revision_id ] }
  end

  test "the teacher's words are the findings reason, else the console or API note, else the attestation; and how it was approved" do
    revise!(lesson_findings_reason_it: "Ho letto i rilievi: la correzione basta.")
    revise!(via: "api", api_reason: "Il bot ha riscritto l'esempio.")
    revise!(via: "console", attested: true, attest_it: "Provata sul telefono.")
    revise!
    assert_equal [ nil, "Provata sul telefono.", "Il bot ha riscritto l'esempio.", "Ho letto i rilievi: la correzione basta." ], CU.all.map(&:reason_it)
    assert_equal %w[web console api web], CU.all.map(&:via)
  end

  # ---- what the student sees ------------------------------------------------------------------------------

  test "the student gets the updates of the topics his course shows and not the others" do
    revise!
    build_hidden_topic!
    assert_equal [ HIDDEN_TOPIC, @topic_key ].sort, CU.all.map(&:topic).sort
    assert_equal [ @topic_key ], CU.for_student(view).map(&:topic)
    assert_equal [ TOPIC_TITLE ], CU.for_student(view).map(&:title_it)
  end

  test "one line per topic and day, grouped by day, newest day first" do
    travel_to(Time.zone.local(2026, 11, 18, 9, 0)) { revise! }
    travel_to(Time.zone.local(2026, 11, 20, 9, 0)) { revise! }
    travel_to(Time.zone.local(2026, 11, 20, 18, 0)) { revise! }
    days = CU.by_day(CU.all)
    assert_equal [ Date.new(2026, 11, 20), Date.new(2026, 11, 18) ], days.map(&:first)
    assert_equal [ 1, 1 ], days.map { |_, list| list.size }
  end

  # ---- «I tuoi commenti» ----------------------------------------------------------------------------------

  def followups(student = @official) = Changelog::Followups.for(student, view(student), CU.for_student(view(student)))

  test "a comment on a lesson, an exercise page or a topic gets one follow-up when the topic is revised after it; the topic is named, not the page" do
    at = Time.zone.local(2026, 11, 18, 10, 0)
    lesson = comment_on(@official, "/topics/#{@topic_key}/lesson", "lesson", at: at, card: 3)
    practice = comment_on(@official, "/topics/#{@topic_key}/practice/#{SKILL}", "practice", at: at + 1.hour)
    topic = comment_on(@official, "/topics/#{@topic_key}", "topic", at: at + 2.hours)
    travel_to(Time.zone.local(2026, 11, 19, 8, 0)) { revise! }
    found = followups.index_by(&:comment_id)
    assert_equal [ lesson.id, practice.id, topic.id ].sort, found.keys.sort
    assert_equal [ TOPIC_TITLE ], found.values.map(&:title_it).uniq
    assert_equal Date.new(2026, 11, 19), found[lesson.id].date
  end

  test "no follow-up when the revision came before the comment, when the page is not about a topic, for another student or for a topic he does not see" do
    travel_to(Time.zone.local(2026, 11, 18, 8, 0)) { revise! }
    comment_on(@official, "/topics/#{@topic_key}/lesson", "lesson", at: Time.zone.local(2026, 11, 18, 9, 0))
    assert_empty followups, "the revision was before the comment"
    comment_on(@official, "/today", "today", at: Time.zone.local(2026, 11, 17, 9, 0))
    comment_on(@official, "/schemas", "schemas", at: Time.zone.local(2026, 11, 17, 9, 0))
    assert_empty followups, "a comment on Oggi is not about a topic"
    comment_on(@trial, "/topics/#{@topic_key}/lesson", "lesson", at: Time.zone.local(2026, 11, 17, 9, 0))
    assert_empty followups, "another student's comment is not his"
    assert_equal 1, followups(@trial).size, "and the trial student's own is his"
    build_hidden_topic!
    comment_on(@official, "/topics/#{HIDDEN_TOPIC}/lesson", "lesson", at: Time.zone.local(2026, 11, 17, 9, 0))
    assert_empty followups, "a topic his course does not show is not named"
  end

  test "the latest revision after the comment is the day named (a topic revised again says so)" do
    comment_on(@official, "/topics/#{@topic_key}", "topic", at: Time.zone.local(2026, 11, 16, 9, 0))
    travel_to(Time.zone.local(2026, 11, 17, 9, 0)) { revise! }
    travel_to(Time.zone.local(2026, 11, 19, 9, 0)) { revise! }
    assert_equal [ Date.new(2026, 11, 19) ], followups.map(&:date)
  end

  test "one group per topic: how many comments, the latest revision, the thread to open when there is one comment" do
    at = Time.zone.local(2026, 11, 16, 9, 0)
    first = comment_on(@official, "/topics/#{@topic_key}", "topic", at: at)
    second = comment_on(@official, "/topics/#{@topic_key}/lesson", "lesson", at: at + 1.hour, card: 2)
    third = comment_on(@official, "/topics/#{@topic_key}/practice/#{SKILL}", "practice", at: at + 2.hours)
    travel_to(Time.zone.local(2026, 11, 17, 9, 0)) { revise! }
    travel_to(Time.zone.local(2026, 11, 19, 9, 0)) { revise! }
    groups = Changelog::Followups.group(followups)
    group = groups.sole
    assert_equal [ @topic_key, TOPIC_TITLE, 3, [ first.id, second.id, third.id ], Date.new(2026, 11, 19) ], [ group.topic, group.title_it, group.count, group.comment_ids, group.date ]
    assert_equal third.id, group.comment_id, "the newest comment is the thread to open"
  end

  # ---- the merge and the visits -------------------------------------------------------------------------

  test "the student's feed merges the entries for him, the topics revised and his follow-ups; the teacher's feed has every entry and every update" do
    travel_to(Time.zone.local(2026, 11, 19, 9, 0)) { revise! }
    comment_on(@official, "/topics/#{@topic_key}", "topic", at: Time.zone.local(2026, 11, 18, 9, 0))
    feed = Changelog::Feed.student(@official, view)
    assert_equal Changelog::Entries.for(:student), feed.entries
    assert_equal 1, feed.updates.size
    assert_equal 1, feed.followups.size
    assert_equal 1, feed.days.size
    teacher = Changelog::Feed.teacher
    assert_equal Changelog::Entries.all, teacher.entries
    assert_equal CU.all, teacher.updates
    assert_empty teacher.followups
    assert_equal [], Changelog::Feed.student(@official, view, followups: false).followups
  end

  test "since keeps the entries by their day and the updates and follow-ups by theirs" do
    travel_to(Time.zone.local(2026, 11, 19, 9, 0)) { revise! }
    comment_on(@official, "/topics/#{@topic_key}", "topic", at: Time.zone.local(2026, 11, 18, 9, 0))
    since = Date.new(2026, 11, 19)
    feed = Changelog::Feed.student(@official, view, since: since)
    assert feed.entries.all? { |e| e.date >= since }
    assert_equal 1, feed.updates.size
    assert_equal 1, feed.followups.size
    later = Changelog::Feed.student(@official, view, since: Date.new(2026, 11, 20))
    assert_empty later.updates
    assert_empty later.followups
  end

  test "what is newer than the last visit is new; before any visit, what is newer than the account" do
    travel_to(Time.zone.local(2026, 11, 19, 9, 0)) { revise! }
    feed = Changelog::Feed.student(@official, view)
    assert_not Changelog::Visits.visited?(@official)
    assert_equal @official.created_at, Changelog::Visits.last_seen(@official)
    assert feed.newer_than?(Time.zone.local(2026, 11, 19, 8, 0)), "the update came after 8:00"
    assert_not feed.newer_than?(Time.zone.local(2026, 11, 25))
    assert_equal 1, feed.new_count(Time.zone.local(2026, 11, 19, 8, 0)) - feed.entries.count { |e| e.at > Time.zone.local(2026, 11, 19, 8, 0) }
    event = Changelog::Visits.record!(@official, new_count: 2)
    assert_equal [ "changelog_viewed", @official.id, { "new" => 2 } ], [ event.kind, event.student_id, JSON.parse(event.payload_json) ]
    assert_equal event.created_at, Changelog::Visits.last_seen(@official)
    assert Changelog::Visits.visited?(@official)
  end

  test "the append-only ledger is not touched: reading writes no row" do
    revise!
    assert_no_difference [ "Decision.count", "AppEvent.count", "Comment.count" ] do
      Changelog::Feed.student(@official, view)
      Changelog::Feed.teacher
    end
  end
end

# The course is not open yet when the teacher approves the topic again: that approval is no news to the official student.
class ChangelogFeedBeforeReleaseTest < ActiveSupport::TestCase
  include ChangelogWorld

  setup { build_student_world(release: false) }

  test "an update approved before the subject was opened to the official student is not shown to him; one after is; a trial student sees the drafts from the start" do
    revise!
    release_course!(@course)
    after = revise!
    updates = Changelog::ContentUpdates
    assert_equal 2, updates.all.size
    assert_equal [ after.id ], updates.for_student(Course::StudentView.new(@official)).map(&:new_revision_id)
    assert_equal 2, updates.for_student(Course::StudentView.new(@trial)).size
  end
end

# D-378: the page keeps the last 14 days of topics revised, lists in full those he started or that are next for him and folds the others.
class ChangelogRecentTest < ActiveSupport::TestCase
  include ChangelogWorld

  setup { build_progress_world }

  def view = Course::StudentView.new(@official)

  def revise_all!(at)
    travel_to(at) { [ @topic_revision, *@progress_topics.values ].each { |revision| revise!(revision) } }
  end

  test "the last 14 days, today included: older updates stay in the ledger and the API, not on the page" do
    revise_all!(20.days.ago)
    revise_all!(13.days.ago)
    revise_all!(2.days.ago)
    all = Changelog::Feed.student(@official, view)
    recent = Changelog::Feed.student(@official, view, recent: true)
    assert_equal 15, all.updates.size
    assert_equal 10, recent.updates.size, "20 days ago is out, 13 days ago and 2 days ago are in"
    assert_equal 2, recent.days.size
    assert_operator recent.updates.map(&:date).min, :>, Date.current - 14
  end

  test "each day lists in full the topics he has started or that are next for him, and folds the others" do
    revise_all!(1.day.ago)
    feed = Changelog::Feed.student(@official, view, recent: true)
    started = [ TOPIC, PROGRESS_STARTED, PROGRESS_EXTRA_DONE ]
    next_key = view.next_topic(view.subject("math"))&.topic&.key
    in_play = (started + [ next_key ]).compact.uniq
    date, shown, folded = feed.day_groups.sole
    assert_equal Date.current - 1, date
    assert_equal in_play.sort, shown.map(&:topic).sort
    assert_equal (@progress_topics.keys + [ TOPIC ] - in_play).sort, folded.map(&:topic).sort
    assert_operator folded.size, :>=, 1, "the topic he has not touched is folded"
  end

  test "an update older than 14 days is neither on the page nor news to the dot" do
    revise_all!(20.days.ago)
    feed = Changelog::Feed.student(@official, view, recent: true)
    assert_empty feed.updates
    assert_empty feed.day_groups
  end

  test "the newest entries are featured, and an entry newer than his last visit is featured too" do
    feed = Changelog::Feed.student(@official, view)
    featured, older = feed.featured_entries(nil)
    assert_equal feed.entries.first(Changelog::Feed::FEATURED_ENTRIES), featured
    assert_equal feed.entries.drop(Changelog::Feed::FEATURED_ENTRIES), older
    since = feed.entries.last.at - 1.day
    featured, older = feed.featured_entries(since)
    assert_equal feed.entries, featured
    assert_empty older
  end
end
