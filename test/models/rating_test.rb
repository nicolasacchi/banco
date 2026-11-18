require "test_helper"
require_relative "../support/ledger_rows"

# D-365: the table of ratings is append-only, the CHECKs hold (stars 1..5, a text of 1 to 2000 characters, at least one of the two, the target's
# shape), a later rating of the same target is a new row and the latest is the current one, and the averages count the official student's current
# stars only.
class RatingTest < ActiveSupport::TestCase
  include LedgerRows

  setup do
    @rows = build_ledger_rows
    @student = @rows["students"]
    @other = Student.create!(key: "prova-1", kind: "student")
    @first = @rows["ratings"] # the ledger's own row: item-1, 4 stars, now
  end

  def item_rating(student: @student, **over)
    Rating.create!({ student: student, client_rating_id: "r-#{SecureRandom.hex(6)}", target_kind: "item", target_key: "item-1", subject: @rows["subjects"],
                     topic_revision: @rows["topic_revisions"], item_revision: @rows["item_revisions"], practice_serve: @rows["practice_serves"], stars: 3,
                     language: "it", trial: student.trial?, created_at: Time.current }.merge(over))
  end

  def lesson_rating(student: @student, **over)
    Rating.create!({ student: student, client_rating_id: "r-#{SecureRandom.hex(6)}", target_kind: "lesson", target_key: "ripasso.math.demo", subject: @rows["subjects"],
                     topic_revision: @rows["topic_revisions"], lesson_revision: @rows["lesson_revisions"], stars: 5, language: "it", trial: student.trial?,
                     created_at: Time.current }.merge(over))
  end

  test "UPDATE and DELETE are refused, by SQL too" do
    assert_raises(ActiveRecord::StatementInvalid) { @first.update_column(:stars, 1) }
    assert_raises(ActiveRecord::StatementInvalid) { Rating.connection.execute("UPDATE ratings SET stars = 1") }
    assert_raises(ActiveRecord::StatementInvalid) { Rating.connection.execute("DELETE FROM ratings") }
  end

  test "stars are 1 to 5 or none; the text is 1 to 2000 characters or none; one of the two at least" do
    [ 0, 6, -1 ].each { |stars| assert_raises(ActiveRecord::StatementInvalid) { item_rating(stars: stars) } }
    assert_nothing_raised { item_rating(stars: 1) }
    assert_nothing_raised { item_rating(stars: 5) }
    assert_nothing_raised { item_rating(stars: nil, text_it: "Solo un commento.") }
    assert_nothing_raised { item_rating(stars: 2, text_it: "x" * 2000) }
    assert_raises(ActiveRecord::StatementInvalid) { item_rating(stars: 2, text_it: "x" * 2001) }
    assert_raises(ActiveRecord::StatementInvalid) { item_rating(stars: 2, text_it: "") }
    assert_raises(ActiveRecord::StatementInvalid) { item_rating(stars: nil, text_it: nil) }
    assert_equal 2000, Rating::TEXT_MAX
  end

  test "the kind, the language and the shape of the target are checked" do
    assert_raises(ActiveRecord::StatementInvalid) { item_rating(target_kind: "page") }
    assert_raises(ActiveRecord::StatementInvalid) { item_rating(language: "fr") }
    assert_nothing_raised { item_rating(language: "en") }
    assert_raises(ActiveRecord::StatementInvalid, "an exercise names its serve") { item_rating(practice_serve: nil) }
    assert_raises(ActiveRecord::StatementInvalid, "an exercise names its revision") { item_rating(item_revision: nil) }
    assert_raises(ActiveRecord::StatementInvalid, "an exercise has no lesson revision") { item_rating(lesson_revision: @rows["lesson_revisions"]) }
    assert_raises(ActiveRecord::StatementInvalid) { lesson_rating(lesson_revision: nil) }
    assert_raises(ActiveRecord::StatementInvalid) { lesson_rating(item_revision: @rows["item_revisions"]) }
    assert_raises(ActiveRecord::StatementInvalid) { lesson_rating(practice_serve: @rows["practice_serves"]) }
  end

  test "a client_rating_id is stored once" do
    item_rating(client_rating_id: "r-same-id-1")
    assert_raises(ActiveRecord::RecordNotUnique) { item_rating(client_rating_id: "r-same-id-1") }
  end

  test "a later rating of the same target is a new row and the latest of each student is the current one" do
    old = item_rating(stars: 2)
    newer = item_rating(stars: 4)
    theirs = item_rating(student: @other, stars: 1)
    lesson = lesson_rating(stars: 5)
    assert_equal [ @first.id, old.id, newer.id, theirs.id, lesson.id ].sort, Rating.pluck(:id).sort, "nothing was replaced"
    assert_equal [ newer.id, theirs.id, lesson.id ].sort, Rating.current.pluck(:id).sort
    assert_equal newer, Rating.latest_for(@student, "item", "item-1")
    assert_equal theirs, Rating.latest_for(@other, "item", "item-1")
    assert_nil Rating.latest_for(@student, "item", "nothing")
  end

  test "the average counts the current stars of the official student; a trial student and a comment without stars never count" do
    item_rating(stars: 2)
    item_rating(stars: 4) # the official student's current one (the ledger's first row, 4 stars, is older)
    item_rating(student: @other, stars: 1)
    item_rating(stars: nil, text_it: "Solo un commento.") # the latest of the student: no stars, so nothing counts
    assert_nil Rating.summary(Rating.items), "the student's latest rating has no star"
    item_rating(stars: 5)
    summary = Rating.summary(Rating.items)
    assert_equal [ 1, 5.0, "5,0" ], [ summary.count, summary.average, summary.average_it ]
    assert_equal [ [ "item", "item-1" ] ], Rating.summaries.keys
    assert_equal({}, Rating.summaries(Rating.trial))
  end

  test "the average of a topic is made of the current stars of its exercises and its lesson" do
    lesson_rating(stars: 5)
    summary = Rating.summary(Rating.of_topic("ripasso.math.demo")) # the ledger's 4 stars on item-1, and the lesson's 5
    assert_equal [ 2, 4.5, "4,5" ], [ summary.count, summary.average, summary.average_it ]
    assert_equal({ [ "item", "item-1" ] => 4.0, [ "lesson", "ripasso.math.demo" ] => 5.0 }, Rating.summaries.transform_values(&:average))
  end

  test "the scopes filter by subject, topic, kind, target, student and time" do
    item = item_rating
    lesson = lesson_rating
    assert_equal [ lesson.id, item.id, @first.id ], Rating.of_subject("math").newest_first.pluck(:id)
    assert_empty Rating.of_subject("history")
    assert_equal [ lesson.id ], Rating.lessons.pluck(:id)
    assert_equal [ lesson.id, item.id, @first.id ], Rating.of_topic("ripasso.math.demo").newest_first.pluck(:id)
    assert_empty Rating.of_topic("ripasso.math.other")
    assert_equal [ lesson.id ], Rating.of_target("ripasso.math.demo").pluck(:id)
    assert_equal [ item.id, @first.id ].sort, Rating.of_student("student").items.pluck(:id).sort
    assert_empty Rating.of_student("prova-1")
    assert_equal 3, Rating.created_since(1.minute.ago).count
    assert_empty Rating.created_since(1.hour.from_now)
  end
end
