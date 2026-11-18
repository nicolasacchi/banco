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
    origin = %w[reply_seen student_reply].include?(kind) ? "student" : "web"
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
    assert_raises(ActiveRecord::StatementInvalid) { make(text_it: "x" * 2001) }
    assert_raises(ActiveRecord::StatementInvalid) { make(text_it: "") }
    assert_raises(ActiveRecord::StatementInvalid) { make(selected_text: "x" * 301) }
    assert_raises(ActiveRecord::StatementInvalid) { event("sneaky") }
    assert_raises(ActiveRecord::StatementInvalid) { event("read", origin: "telepathy") }
    assert_nothing_raised { event("read", origin: "api") } # D-327
    assert_raises(ActiveRecord::StatementInvalid) { event("reply") }
    assert_raises(ActiveRecord::StatementInvalid) { event("reply", text_it: "x" * 2001) }
    assert_raises(ActiveRecord::StatementInvalid) { event("reply_seen", origin: "web") }
    assert_raises(ActiveRecord::StatementInvalid) { event("read", origin: "student") }
    assert_raises(ActiveRecord::StatementInvalid) { event("student_reply", origin: "web", text_it: "Grazie.") } # D-342
    assert_raises(ActiveRecord::StatementInvalid) { event("student_reply", origin: "api", text_it: "Grazie.") }
    assert_raises(ActiveRecord::StatementInvalid) { event("student_reply") }
    assert_raises(ActiveRecord::StatementInvalid) { event("student_reply", text_it: "") }
    assert_raises(ActiveRecord::StatementInvalid) { event("student_reply", text_it: "x" * 2001) }
    assert_nothing_raised { event("student_reply", text_it: "x" * 1500) } # D-361: 2000, was 500
    assert_nothing_raised { event("student_reply", text_it: "x" * 2000) }
    assert_nothing_raised { make(text_it: "x" * 1500, selected_text: "y" * 300) }
    assert_nothing_raised { make(text_it: "x" * 2000) }
    assert_nothing_raised { make(page_kind: "civics") }
    assert_nothing_raised { make(page_kind: "not_found", page_path: "/not-found/topics/x") }
  end

  test "the longest text of a comment and of a follow-up is 2000 (D-361)" do
    assert_equal 2000, Comment::TEXT_MAX
  end

  test "Intake and StudentReply take 1500 and 2000 characters and refuse 2001 (D-361)" do
    view = Course::StudentView.new(@student)
    params = ->(text) { ActionController::Parameters.new(client_comment_id: "c-#{SecureRandom.hex(8)}", reason: "other", text_it: text, page_path: "/today") }
    [ 1500, 2000 ].each do |n|
      result = Comments::Intake.call(student: @student, course_view: view, params: params.("x" * n))
      assert_equal [ :recorded, n ], [ result.status, result.comment.text_it.length ]
    end
    result = Comments::Intake.call(student: @student, course_view: view, params: params.("x" * 2001))
    assert_equal [ :invalid, "text_it" ], [ result.status, result.error ]
    event("reply", text_it: "Ecco.")
    reply = ->(text) { Comments::StudentReply.call(student: @student, comment_id: @comment.id, text_it: text, client_reply_id: "r-#{SecureRandom.hex(8)}") }
    [ 1500, 2000 ].each { |n| assert_equal [ :recorded, n ], reply.("y" * n).then { |r| [ r.status, r.event.text_it.length ] } }
    assert_equal [ :invalid, "text_it" ], reply.("y" * 2001).then { |r| [ r.status, r.error ] }
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

  # ---- D-342: the student answers the teacher's reply

  test "a follow-up after a reply waits for the teacher again: sent, then read, then answered by the next reply" do
    event("reply", text_it: "Guarda la scheda 2.")
    assert_equal "answered", @comment.reload.state
    event("student_reply", text_it: "Non ho capito l'esempio.")
    assert_equal "sent", @comment.reload.state
    event("read")
    assert_equal "read", @comment.reload.state
    event("reply", text_it: "Te lo spiego meglio.")
    assert_equal "answered", @comment.reload.state
    event("student_reply", text_it: "Ora sì.")
    event("student_reply", text_it: "Grazie.")
    assert_equal "sent", @comment.reload.state
  end

  test "a follow-up after resolved reopens the comment; resolved after the follow-up closes it again" do
    event("reply", text_it: "Ecco.")
    event("resolved")
    assert_equal "closed", @comment.reload.state
    event("student_reply", text_it: "Ma non ho capito.")
    assert_equal "sent", @comment.reload.state
    event("read")
    assert_equal "read", @comment.reload.state
    event("resolved")
    assert_equal "closed", @comment.reload.state
    event("reopened")
    assert_equal "read", @comment.reload.state, "back to where the last message and the read put it"
  end

  test "the thread is the comment, the replies and the follow-ups in id order, and nothing else" do
    event("read")
    event("reply", text_it: "Uno.")
    event("reply_seen")
    event("student_reply", text_it: "Due.")
    event("resolved")
    thread = @comment.reload.thread
    assert_equal [ :student, :teacher, :student ], thread.map(&:from)
    assert_equal [ @comment.text_it, "Uno.", "Due." ], thread.map(&:text_it)
    assert_equal [ nil, "reply", "student_reply" ], thread.map { |m| m.event&.kind }
    assert_equal 1, @comment.student_replies.size
  end

  test "a follow-up is not a reply the student has to see: unread_reply? is about the teacher's replies" do
    event("reply", text_it: "Uno.")
    event("reply_seen")
    event("student_reply", text_it: "Grazie.")
    assert_not @comment.reload.unread_reply?
    event("reply", text_it: "Prego.")
    assert @comment.reload.unread_reply?
    assert_equal 1, Comment.unread_reply_count(@student)
  end
end
