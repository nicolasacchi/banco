namespace :banco do
  namespace :token do
    # The token is printed once on stdout and never stored in plaintext (D-05).
    # The operator runs it in the container and stores the output in the password
    # manager (vault Banco, item banco-agent-<kind>, field token).
    desc "Issue an agent token and print it once: ROLE=agent_claude|agent_omp|ci [LABEL=text]"
    task issue: :environment do
      role = ENV["ROLE"].presence or abort "ROLE=#{ApiToken::ROLES.join('|')} is required"
      abort "unknown ROLE #{role}" unless ApiToken::ROLES.include?(role)
      $stdout.puts ApiToken.issue!(role: role, label: ENV.fetch("LABEL", role))
    end

    desc "Revoke a token by its public id (the 8 characters after bnc_): ID=abcd1234 [REASON=text]"
    task revoke: :environment do
      token = ApiToken.find_by(public_id: ENV["ID"].to_s) or abort "unknown ID"
      ApiTokenRevocation.create!(api_token: token, reason: ENV["REASON"].presence)
      puts "revoked #{token.public_id}"
    end
  end
end
