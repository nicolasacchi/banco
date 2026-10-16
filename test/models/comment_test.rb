require "test_helper"

# D-304: the tables are append-only, the CHECKs hold, and the state of a comment is derived from its events.
class CommentTest < ActiveSupport::TestCase
  setup do
    @student = Student.create!(key: "student", kind: "student", created_at: Time.current)
    @comment = make
  end

  def make(**attrs)
    Comment.create!({ student: @student, client_comment_id: "c-#{SecureRandom.hex(6)}", reason: "error", page_path: "/today", page_kind: "today", created_at: Time.current }.merge(attrs))
  end

  def event(kind, comment: @comment, **attrs)
    origin = kind == "reply_seen" ? "student" : "web"
    CommentEvent.create!({ comment: comment, kind: kind, origin: origin, actor: origin == "student" ? "student" : "nik", created_at: Time.current }.merge(attrs))
  end

  test "both tables refuse UPDATE and DELETE, by SQL too" do
    e = event("read")
    [ @comment, e ].each do |row|
      table = row.class.table_name
      assert_raises(ActiveRecord::StatementInvalid) { row.class.connection.execute("UPDATE #{table} SET created_at = created_at") }
      assert_raises(ActiveRecord::StatementInvalid) { row.class.connection.execute("DELETE FROM #{table}") }
      assert_raises(ActiveRecord::StatementInvalid) { row.update_column(:created_at, 1.day.ago) }
    end
  end

  test "the CHECKs refuse an unknown reason, kind, page kind, origin, over-long text and a reply without text" do
    assert_raises(ActiveRecord::StatementInvalid) { make(reason: "angry") }
    assert_raises(ActiveRecord::StatementInvalid) { make(page_kind: "elsewhere") }
    assert_raises(ActiveRecord::StatementInvalid) { make(text_it: "x" * 501) }
    assert_raises(ActiveRecord::StatementInvalid) { make(text_it: "") }
    assert_raises(ActiveRecord::StatementInvalid) { make(selected_text: "x" * 301) }
    assert_raises(ActiveRecord::StatementInvalid) { event("sneaky") }
    assert_raises(ActiveRecord::StatementInvalid) { event("read", origin: "api") }
    assert_raises(ActiveRecord::StatementInvalid) { event("reply") }
    assert_raises(ActiveRecord::StatementInvalid) { event("reply", text_it: "x" * 2001) }
    assert_raises(ActiveRecord::StatementInvalid) { event("reply_seen", origin: "web") }
    assert_raises(ActiveRecord::StatementInvalid) { event("read", origin: "student") }
    assert_nothing_raised { make(text_it: "x" * 500, selected_text: "y" * 300) }
  end

  test "client_comment_id is unique" do
    assert_raises(ActiveRecord::RecordNotUnique) { make(client_comment_id: @comment.client_comment_id) }
  end

  test "the state is derived: sent, read, answered, closed, and reopened goes back" do
    assert_equal "sent", @comment.reload.state
    event("read")
    assert_equal "read", @comment.reload.state
    event("reply", text_it: "Ecco.")
    assert_equal "answered", @comment.reload.state
    event("resolved")
    assert_equal "closed", @comment.reload.state
    event("reopened")
    assert_equal "answered", @comment.reload.state
  end

  test "a reply is unread until the student has seen it, and again after the next reply" do
    assert_not @comment.reload.unread_reply?
    event("reply", text_it: "Uno.")
    assert @comment.reload.unread_reply?
    assert_equal 1, Comment.unread_reply_count(@student)
    event("reply_seen")
    assert_not @comment.reload.unread_reply?
    assert_equal 0, Comment.unread_reply_count(@student)
    event("reply", text_it: "Due.")
    assert @comment.reload.unread_reply?
  end

  test "one student's replies do not count for another" do
    other = Student.create!(key: "prova-1", kind: "student", created_at: Time.current)
    event("reply", text_it: "Uno.")
    assert_equal 0, Comment.unread_reply_count(other)
  end
end
