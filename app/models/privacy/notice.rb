module Privacy
  # The operator's own words in the privacy notice (D-357). They come from the environment, never from git, and each has a neutral
  # default in the locale (config/locales/privacy.*.yml, `privacy.defaults`), so a fresh installation shows a complete page. An
  # unset or blank variable means the default. The values of the _IT variables are Italian text and are shown as written in both
  # languages.
  module Notice
    VARIABLES = {
      controller: "BANCO_PRIVACY_CONTROLLER_IT",
      contact: "BANCO_PRIVACY_CONTACT",
      hosting: "BANCO_PRIVACY_HOSTING_IT",
      retention: "BANCO_PRIVACY_RETENTION_IT"
    }.freeze
    AI_PROVIDER_VARIABLE = "BANCO_PRIVACY_AI_PROVIDER"
    AI_PROVIDER_DEFAULT = "Anthropic (Claude)".freeze
    GARANTE_URL = "https://www.garanteprivacy.it".freeze

    module_function

    # { controller:, contact:, hosting:, ai_provider:, retention: } as strings, ready to put in a sentence.
    def values(env = ENV)
      VARIABLES.to_h { |key, name| [ key, env[name].to_s.strip.presence || I18n.t("privacy.defaults.#{key}") ] }
                .merge(ai_provider: env[AI_PROVIDER_VARIABLE].to_s.strip.presence || AI_PROVIDER_DEFAULT)
    end
  end
end
