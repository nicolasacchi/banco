require "test_helper"
require_relative "../support/student_ui_rows"
require_relative "../support/multi_user"

# D-217: who is who. The identity matrix (teacher, guest, official student, trial student, an
# unmapped student, no map at all, two groups, a peer that is not the edge), the env parsing and
# the logout link.
class MultiUserIdentityTest < ActionDispatch::IntegrationTest
  include StudentUiRows
  include MultiUser

  test "the env lists parse logins with an at sign and a dot, and drop what is malformed" do
    with_env("BANCO_STUDENT_USERS" => "a@b.test=student, kid=prova-1 ,bad, =x,k2=Bad_Key,k3=preview,k4=ok-2,k5=") do
      assert_equal({ "a@b.test" => "student", "kid" => "prova-1", "k4" => "ok-2" }, Banco::EdgeProxy.student_map)
    end
    with_env("BANCO_GUEST_USERS" => "ospite@example.test, g2") do
      assert_equal %w[ospite@example.test g2], Banco::EdgeProxy.guest_users
    end
    with_env("BANCO_STUDENT_USERS" => nil) { assert_empty Banco::EdgeProxy.student_map }
    with_env("BANCO_LOGOUT_URL" => "https://auth.example.test/logout?rd=https://app.example.test/") { assert_match %r{\Ahttps://auth}, Banco::EdgeProxy.logout_url }
    with_env("BANCO_LOGOUT_URL" => "javascript:alert(1)") { assert_nil Banco::EdgeProxy.logout_url }
  end

  test "identity matrix on the teacher page and the student page" do
    {
      "teacher" => [ TEACHER, 200, 403 ],
      "second teacher" => [ TEACHER_B, 200, 403 ],
      "guest" => [ GUEST, 200, 403 ],
      "official student" => [ OFFICIAL, 403, 200 ],
      "trial student" => [ TRIAL, 403, 200 ],
      "unmapped student" => [ UNMAPPED, 403, 403 ],
      "no login" => [ {}, 403, 403 ]
    }.each do |who, (headers, teacher_status, student_status)|
      assert_equal teacher_status, get_as(headers, "/teacher"), "#{who} on /teacher"
      assert_equal student_status, get_as(headers, "/diagnosis"), "#{who} on /diagnosis"
    end
  end

  test "a guest needs the group and the list, a teacher in both lists stays a teacher" do
    assert_equal 403, get_as({ "Remote-User" => "guest-a@example.test", "Remote-Groups" => "users" }, "/teacher")
    assert_equal 403, get_as({ "Remote-User" => "stranger", "Remote-Groups" => "banco-guest" }, "/teacher")
    with_env("BANCO_GUEST_USERS" => "guest-a@example.test,nik") do
      get_as({ "Remote-User" => "nik", "Remote-Groups" => "banco-teacher,banco-guest" }, "/teacher")
      assert_response :success
      assert_select "#read-only-notice", 0
      assert_select "#access-line", /Accesso: nik · insegnante/
    end
  end

  test "teacher and student groups together make a teacher only" do
    both = { "Remote-User" => "nik", "Remote-Groups" => "banco-teacher,banco-student" }
    with_env("BANCO_STUDENT_USERS" => "nik=prova-9") do
      assert_equal 200, get_as(both, "/teacher")
      assert_equal 403, get_as(both, "/diagnosis")
    end
    assert_nil Student.find_by(key: "prova-9")
  end

  test "an unmapped student gets the Italian page and no student row" do
    assert_equal 403, get_as(UNMAPPED, "/diagnosis")
    assert_select "#not-configured", /Account non configurato: chiedi all'insegnante/
    assert_equal 0, Student.count
    on(:web, "/diagnosis/warmup", headers: UNMAPPED, remote_addr: EDGE)
    assert_response :forbidden
  end

  test "an unmapped student writes nothing: every student write is refused and no row appears" do
    before = [ Student.count, Attempt.count, DiagnosisRun.count, DiagnosisEvent.count, AppEvent.count ]
    %w[/diagnosis/preferences /diagnosis/warmup/answers /diagnosis/warmup/complete].each do |path|
      on(:web, path, method: :post, headers: UNMAPPED.merge("Content-Type" => "application/json", "Accept" => "application/json"),
                     params: {}.to_json, remote_addr: EDGE)
      assert_response :forbidden, "POST #{path}"
    end
    assert_equal before, [ Student.count, Attempt.count, DiagnosisRun.count, DiagnosisEvent.count, AppEvent.count ]
  end

  test "each mapped login acts as its own student row" do
    get_as(OFFICIAL, "/diagnosis")
    get_as(TRIAL, "/diagnosis")
    get_as(TRIAL_B, "/diagnosis")
    assert_equal %w[prova-1 prova-2 student], Student.order(:key).pluck(:key)
    assert_predicate Student.find_by(key: "prova-1"), :trial?
    assert_not Student.find_by(key: "student").trial?
    assert Student.find_by(key: "student").official?
  end

  test "with the map unset any student login is the official student" do
    with_env("BANCO_STUDENT_USERS" => nil) do
      assert_equal 200, get_as({ "Remote-User" => "anyone", "Remote-Groups" => "banco-student" }, "/diagnosis")
      assert_equal [ "student" ], Student.pluck(:key)
      assert_equal 200, get_as({ "Remote-User" => "someone-else", "Remote-Groups" => "banco-student" }, "/diagnosis")
      assert_equal [ "student" ], Student.pluck(:key)
    end
  end

  test "a configured map with a bad pair fails closed: the map stays configured and unmapped logins are refused" do
    [ "kid-a=preview", "kid-a=Bad_Key", "kid-a", ",", "=student" ].each do |value|
      with_env("BANCO_STUDENT_USERS" => value) do
        assert Banco::EdgeProxy.student_map_configured?, value
        assert_equal 403, get_as(OFFICIAL, "/diagnosis"), value
        assert_select "#not-configured"
      end
    end
    assert_equal 0, Student.count
    with_env("BANCO_STUDENT_USERS" => "kid-a=student,oops,trial-x=prova-1") do
      assert_equal 200, get_as(OFFICIAL, "/diagnosis")
      assert_equal 403, get_as(UNMAPPED, "/diagnosis")
      assert_equal [ 2 ], Banco::EdgeProxy.student_map_problems
    end
    with_env("BANCO_STUDENT_USERS" => "  ") do
      assert_not Banco::EdgeProxy.student_map_configured?
      assert_equal 200, get_as(UNMAPPED, "/diagnosis")
    end
  end

  test "a peer that is not the edge is nobody, whatever the headers say" do
    [ TEACHER, GUEST, OFFICIAL, TRIAL ].each do |headers|
      %w[/teacher /diagnosis].each do |path|
        on(:web, path, headers: headers, remote_addr: "10.0.0.5")
        assert_response :forbidden, "#{headers['Remote-User']} #{path}"
      end
    end
  end

  test "the logout link shows on the teacher, guest and student pages only when BANCO_LOGOUT_URL is set" do
    build_ui_subject
    url = "https://auth.example.test/logout?rd=https://app.example.test/"
    [ [ TEACHER, "/teacher" ], [ GUEST, "/teacher" ], [ OFFICIAL, "/diagnosis" ], [ TRIAL, "/diagnosis" ] ].each do |headers, path|
      get_as(headers, path)
      assert_select "#logout-link", 0, "#{headers['Remote-User']} without the variable"
      with_env("BANCO_LOGOUT_URL" => url) do
        get_as(headers, path)
        assert_select "a#logout-link[href=?]", url, text: "Esci"
      end
    end
    with_env("BANCO_LOGOUT_URL" => url) do
      get_as(UNMAPPED, "/diagnosis")
      assert_select "a[href=?]", url
    end
  end

  test "teacher pages say who is logged in" do
    get_as(TEACHER_B, "/teacher")
    assert_select "#access-line", /Accesso: teacher-a@example.test · insegnante/
    get_as(GUEST, "/teacher")
    assert_select "#access-line", /Accesso: guest-a@example.test · ospite/
  end
end
