# Free pages, release 2 (D-261, D-289; SPEC B): the namespace, the switch and the constants shared by the pages origin,
# the validation and the lesson block. Rails stores bytes, hashes them, scans them and serves them; it never runs them.
module Pages
  # The eight seeds a student can ever receive (B5): a finite set, so validation runs every one of them. Seed 0 is the
  # teacher's box. Chosen once, never changed (a page revision was validated with exactly these).
  SEEDS = [ 314_159_265, 271_828_182, 161_803_398, 141_421_356, 173_205_080, 223_606_797, 235_702_260, 264_575_131 ].freeze

  MEDIA_TYPES = {
    "mjs" => "text/javascript; charset=utf-8", "js" => "text/javascript; charset=utf-8", "css" => "text/css; charset=utf-8",
    "svg" => "image/svg+xml", "png" => "image/png", "webp" => "image/webp", "jpg" => "image/jpeg", "jpeg" => "image/jpeg",
    "woff2" => "font/woff2", "html" => "text/html; charset=utf-8"
  }.freeze

  VALIDATION_HOST = "banco-pages-internal"

  module_function

  # BANCO_PAGES_ENABLED, default 0 until release 2 ships (B4); a container restart switches it, not a deploy.
  def enabled? = ENV.fetch("BANCO_PAGES_ENABLED", "0") == "1"

  # The seed of a student for a page: sha256(student key, page key) mod 8 (B5).
  def seed_for(student_key, page_key)
    SEEDS[Digest::SHA256.hexdigest("#{student_key}\n#{page_key}").to_i(16) % SEEDS.size]
  end

  def teacher_seed = SEEDS.first

  def media_type(path) = MEDIA_TYPES[File.extname(path.to_s).delete_prefix(".").downcase]

  # ---- origins (fixed per mount, never from a request) ---------------------------------------------------------

  # The public origin of the pages (BANCO_PAGES_ORIGIN) and of the app that frames them (BANCO_APP_ORIGIN).
  def origin(env = ENV) = env["BANCO_PAGES_ORIGIN"].presence || "http://127.0.0.1:#{Banco::Listeners.ports(env).fetch(:pages)}"
  def app_origin(env = ENV) = env["BANCO_APP_ORIGIN"].presence || "http://127.0.0.1:#{Banco::Listeners.ports(env).fetch(:web)}"

  # The validation mount, on the harness listener under another host name: the page is served from
  # http://banco-pages-internal:PORT and framed by the host page on the harness origin (Harness.base_url).
  def validation_parent = Validation::Harness.base_url
  def validation_origin = Validation::Harness.base_url.sub(%r{\A(https?://)[^:/]+}, "\\1#{VALIDATION_HOST}")

  # The URL of the shell of a revision on a mount, with the trailing slash (B3).
  def shell_url(sha, kit, base: origin) = "#{base}/p/#{sha}/k#{kit}/"
end
