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
    origin = %w[reply_seen student_reply student_withdrawn].include?(kind) ? "student" : "web"
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

  # ---- D-397: the student deletes his own comment before any reply ----

  test "student_withdrawn is a kind of the student's alone: origin student, no text needed, refused from any other origin" do
    assert_includes CommentEvent::KINDS, "student_withdrawn"
    assert_not_includes CommentEvent::TEACHER_KINDS, "student_withdrawn"
    assert_nothing_raised { event("student_withdrawn") }
    other = make
    assert_raises(ActiveRecord::StatementInvalid) { event("student_withdrawn", comment: other, origin: "web") }
    assert_raises(ActiveRecord::StatementInvalid) { event("student_withdrawn", comment: other, origin: "api") }
    assert_raises(ActiveRecord::StatementInvalid) { event("student_withdrawn", comment: other, origin: "console") }
  end

  test "a withdrawn comment is in the state withdrawn, which nothing after it changes, and it is never due" do
    assert_includes Comment::STATES, "withdrawn"
    event("read")
    assert_equal "read", @comment.reload.state
    assert @comment.waiting_for_teacher?
    event("student_withdrawn", origin: "student")
    assert @comment.reload.withdrawn?
    assert_equal "withdrawn", @comment.state
    assert_not @comment.waiting_for_teacher?
    assert_nil @comment.waiting_since
    assert_not @comment.late?
    assert_nil @comment.due_in_hours
    assert_not @comment.student_followup?
    assert_empty Comments::Due.rows([ @comment ])
    event("resolved")
    assert_equal "withdrawn", @comment.reload.state, "a later teacher row does not bring it back"
    assert_not make.withdrawn?
  end

  test "StudentWithdraw records the student's own unanswered comment once, and refuses a reply, another student's and a non-student" do
    row = Comments::StudentWithdraw.call(student: @student, comment_id: @comment.id)
    assert_equal :recorded, row.status
    assert_equal [ "student_withdrawn", "student", @student.key, nil ], [ row.event.kind, row.event.origin, row.event.actor, row.event.text_it ]
    assert_equal [ :recorded, row.event.id ], Comments::StudentWithdraw.call(student: @student, comment_id: @comment.id).then { |r| [ r.status, r.event.id ] }
    assert_equal 1, CommentEvent.where(comment: @comment, kind: "student_withdrawn").count
    assert Comment.exists?(@comment.id), "the ledger keeps the comment"

    answered = make
    event("reply", comment: answered, text_it: "Guarda.")
    refused = Comments::StudentWithdraw.call(student: @student, comment_id: answered.id)
    assert_equal [ :invalid, "teacher_replied" ], [ refused.status, refused.error ]
    assert_not answered.reload.withdrawn?
    event("student_reply", comment: answered, text_it: "Grazie.")
    assert_equal :invalid, Comments::StudentWithdraw.call(student: @student, comment_id: answered.id).status

    stranger = Student.create!(key: "prova-1", kind: "student", created_at: Time.current)
    mine = make
    assert_equal :missing, Comments::StudentWithdraw.call(student: stranger, comment_id: mine.id).status
    assert_equal :missing, Comments::StudentWithdraw.call(student: @student, comment_id: "nope").status
    assert_not mine.reload.withdrawn?
    teacher = Student.create!(key: "preview", kind: "preview", created_at: Time.current)
    assert_equal :invalid, Comments::StudentWithdraw.call(student: teacher, comment_id: mine.id).status
  end

  test "the student's inbox leaves a withdrawn comment out of every tab, the teacher's inbox counts it as withdrawn" do
    kept = make
    gone = make
    event("student_withdrawn", comment: gone, origin: "student")
    inbox = Comments::StudentInbox.new(@student)
    assert_equal [ kept.id, @comment.id ].sort, inbox.rows.map { |r| r.comment.id }.sort
    assert_equal({ "all" => 2, "new" => 0, "waiting" => 2, "closed" => 0 }, inbox.counts)
    counts = Comments::Inbox.counts
    assert_equal [ 2, 1, 0 ], [ counts["sent"], counts["withdrawn"], counts["late"] ]
    assert_equal [ gone.id ], Comments::Inbox.new(state: "withdrawn").comments.map(&:id)
    assert_equal [ gone.id ], Comments::ApiRows.list(state: "withdrawn").map(&:id)
    assert_not_includes Comments::ApiRows.list(state: "open").map(&:id), gone.id
    assert_includes Comments::ApiRows.list(state: "all").map(&:id), gone.id
    assert_equal "ritirato dallo studente", Comments::ApiRows.summary(gone.reload)[:state_it]
    assert_nil Comments::ApiRows.summary(kept)[:state_it]
  end

  test "the teacher's Responder refuses every action on a withdrawn comment" do
    event("student_withdrawn", origin: "student")
    request = DecisionRecorder::Console.new(login: "nik", os_user: "nik")
    ENV["BANCO_DECISIONS_ENABLED"] = "1"
    ENV["BANCO_TEACHER_USERS"] = "nik"
    %w[reply read resolved reopened].each do |kind|
      error = assert_raises(DecisionRecorder::Invalid) { Comments::Responder.call(request: request, comment_id: @comment.id, kind: kind, text_it: "Ciao") }
      assert_equal [ "the comment was withdrawn by the student" ], error.reasons, kind
    end
    assert_equal %w[student_withdrawn], @comment.events.reload.map(&:kind)
    assert_equal "Lo studente ha ritirato il commento: non c'è niente da fare.", Teacher::Wording.italian("the comment was withdrawn by the student")
  ensure
    ENV.delete("BANCO_DECISIONS_ENABLED")
    ENV.delete("BANCO_TEACHER_USERS")
  end
end
