require "yaml"

module Privacy
  # The access portal as the account page describes it (D-357): its address from BANCO_AUTH_URL (only an http or https address
  # counts; otherwise the page says «the address you use to sign in») and its numbers from config/banco/account.yml, which mirror
  # the portal's own settings.
  module Portal
    PATH = "config/banco/account.yml".freeze
    KEYS = %w[session_hours inactivity_hours remember_months].freeze
    LOCKOUT_KEYS = %w[wrong_passwords within_minutes ban_hours].freeze

    module_function

    def url(env = ENV)
      url = env["BANCO_AUTH_URL"].to_s.strip
      url.match?(%r{\Ahttps?://\S+\z}) ? url : nil
    end

    def settings = @settings ||= YAML.safe_load_file(Rails.root.join(PATH)).freeze

    # The numbers as the words of a sentence ("12 ore", "1 ora", "5"), in the current locale.
    def phrases
      s = settings
      lockout = s.fetch("lockout")
      {
        session: unit(:hours, s.fetch("session_hours")),
        inactivity: unit(:hours, s.fetch("inactivity_hours")),
        remember: unit(:months, s.fetch("remember_months")),
        wrong_passwords: lockout.fetch("wrong_passwords").to_s,
        window: unit(:minutes, lockout.fetch("within_minutes")),
        ban: unit(:hours, lockout.fetch("ban_hours"))
      }
    end

    def unit(name, count) = I18n.t("account.units.#{name}", count: count)
  end
end
