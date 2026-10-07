# Logins for the three roles and the trial students (D-217). Every login here is invented.
module MultiUser
  EDGE = ListenerHelpers::EDGE_IP
  TEACHER = { "Remote-User" => "nik", "Remote-Groups" => "banco-teacher" }.freeze
  TEACHER_B = { "Remote-User" => "teacher-a@example.test", "Remote-Groups" => "banco-teacher" }.freeze
  GUEST = { "Remote-User" => "guest-a@example.test", "Remote-Groups" => "banco-guest" }.freeze
  OFFICIAL = { "Remote-User" => "kid-a", "Remote-Groups" => "banco-student" }.freeze
  TRIAL = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  TRIAL_B = { "Remote-User" => "trial-y", "Remote-Groups" => "banco-student" }.freeze
  UNMAPPED = { "Remote-User" => "kid-z", "Remote-Groups" => "banco-student" }.freeze
  ENV_KEYS = %w[BANCO_EDGE_PROXY BANCO_TEACHER_USERS BANCO_GUEST_USERS BANCO_STUDENT_USERS BANCO_LOGOUT_URL BANCO_DECISIONS_ENABLED].freeze

  def self.included(base)
    base.setup do
      @saved_multi_env = ENV.to_h.slice(*ENV_KEYS)
      ENV["BANCO_EDGE_PROXY"] = "#{EDGE}/32"
      ENV["BANCO_TEACHER_USERS"] = "nik,teacher-a@example.test"
      ENV["BANCO_GUEST_USERS"] = "guest-a@example.test"
      ENV["BANCO_STUDENT_USERS"] = "kid-a=student,trial-x=prova-1,trial-y=prova-2"
      ENV.delete("BANCO_LOGOUT_URL")
    end
    base.teardown do
      ENV_KEYS.each { |k| @saved_multi_env.key?(k) ? ENV[k] = @saved_multi_env[k] : ENV.delete(k) }
    end
  end

  def get_as(headers, path)
    on(:web, path, headers: headers, remote_addr: EDGE)
    response.status
  end
end
