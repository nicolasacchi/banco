# Content security policy of the app pages (X-02). In phase 1a the student's
# browser runs only our code: one origin, a per-request nonce for the scripts that
# importmap-rails emits in line, and style-src 'unsafe-inline' because MathLive and
# KaTeX position their output with style attributes. script-src never contains
# 'unsafe-inline'. Agent figures are served by ItemAssetsController with their own
# stricter policy.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src :self
    policy.style_src :self, :unsafe_inline
    policy.img_src :self, :data
    policy.font_src :self
    policy.connect_src :self
    policy.frame_src :none
    # No app page is framed anywhere (D-261, SPEC B4): a free page that navigates its own frame to a banco URL gets a blocked frame.
    policy.frame_ancestors :none
    policy.object_src :none
    policy.base_uri :none
    policy.form_action :self
  end

  # A fresh random nonce per request, not the session id: Turbo-less pages have
  # no session to hang it on, and a nonce must never repeat.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end

# ... and the old header for browsers that do not read frame-ancestors (Rails sends SAMEORIGIN by default).
Rails.application.config.action_dispatch.default_headers = Rails.application.config.action_dispatch.default_headers.merge("X-Frame-Options" => "DENY")
