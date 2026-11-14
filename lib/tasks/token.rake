namespace :banco do
  namespace :token do
    # The token is printed once on stdout and never stored in plaintext (D-05).
    # The operator runs it in the container and stores the output in the password
    # manager (vault Banco, item banco-agent-<kind>, field token).
    #
    # A token expires after EXPIRES_DAYS days (default 90, D-327); a token that never expires is not issued. The public API's
    # roles are bot_read (reads only) and teacher (reads, decisions and comment actions as TEACHER=<login>, a login of
    # BANCO_TEACHER_USERS, checked again at every use). A bot_read or teacher token renews itself on use (D-330): EXPIRES_DAYS
    # is its lifetime, and it expires only after that many days without a request; revoke it to stop it.
    desc "Issue a token and print it once: ROLE=agent_claude|agent_omp|ci|bot_read|teacher [LABEL=text] [EXPIRES_DAYS=90] [TEACHER=login (role teacher)]"
    task issue: :environment do
      role = ENV["ROLE"].presence or abort "ROLE=#{ApiToken::ROLES.join('|')} is required"
      abort "unknown ROLE #{role}" unless ApiToken::ROLES.include?(role)
      days = ENV.fetch("EXPIRES_DAYS", "90")
      abort "EXPIRES_DAYS is a whole number of days, at least 1 (a token always expires)" unless days.match?(/\A[1-9]\d{0,4}\z/)
      days = days.to_i
      teacher = ENV["TEACHER"].presence
      abort "TEACHER=<login from BANCO_TEACHER_USERS> is required for a teacher token" if role == "teacher" && teacher.nil?
      abort "TEACHER is for role teacher only" if teacher && role != "teacher"
      abort "TEACHER #{teacher.first(40).inspect} is not in BANCO_TEACHER_USERS" if teacher && !Banco::EdgeProxy.teacher_users.include?(teacher)
      $stdout.puts ApiToken.issue!(role: role, label: ENV.fetch("LABEL", role), expires_at: days.days.from_now, teacher_login: teacher)
    end

    desc "List the tokens (never the secret): public id, role, label, teacher, effective expiry (renewals included), state"
    task list: :environment do
      puts format("%-8s  %-12s  %-20s  %-12s  %-20s  %s", "ID", "ROLE", "LABEL", "TEACHER", "EXPIRES_AT", "STATE")
      ApiToken.order(:id).each do |token|
        expires_at = token.effective_expires_at
        state = token.revoked? ? "revoked" : (token.expired? ? "expired" : "active")
        puts format("%-8s  %-12s  %-20s  %-12s  %-20s  %s", token.public_id, token.role, token.label.first(20), token.teacher_login || "-",
                    expires_at&.utc&.strftime("%Y-%m-%d %H:%M") || "never", state)
      end
    end

    desc "Revoke a token by its public id (the 8 characters after bnc_): ID=abcd1234 [REASON=text]"
    task revoke: :environment do
      token = ApiToken.find_by(public_id: ENV["ID"].to_s) or abort "unknown ID"
      ApiTokenRevocation.create!(api_token: token, reason: ENV["REASON"].presence)
      puts "revoked #{token.public_id}"
    end
  end
end
