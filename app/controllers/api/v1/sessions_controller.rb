module Api
  module V1
    # POST /api/v1/sessions {role, agent, model}: a working session (A-04). The model
    # is declared, not proven (A-08): the provider rules guard against mistakes.
    class SessionsController < Api::BaseController
      def create
        body = parse_json_body or return
        role, agent, model = %w[role agent model].map { |k| body[k].to_s.strip }
        return refuse("E-FILES", "role", "role is one of #{AgentSession::ROLES.join(', ')}", "banco session new --role ROLE --agent NAME --model MODEL", 422) unless AgentSession::ROLES.include?(role)
        return refuse("E-FILES", "agent", "give --agent (the program, for example omp or claude-code)", "banco session new --role #{role} --agent NAME --model MODEL", 422) if agent.empty? || agent.size > 64
        return refuse("E-FILES", "model", "give --model (the model the session runs on)", "banco session new --role #{role} --agent #{agent} --model MODEL", 422) if model.empty? || model.size > 96

        session = AgentSession.new(label: agent, role: role, agent: agent, model: model)
        reason = Providers.refusal(session)
        return refuse("E-PROVIDER-NOT-ALLOWED", "model", reason, "see config/banco/providers.yml", 422) if reason

        session.save!
        render json: session.to_h.merge(next: "export BANCO_SESSION=#{session.id}"), status: :created
      end
    end
  end
end
