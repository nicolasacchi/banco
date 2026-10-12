require_relative "lesson2_page_world"
require_relative "lesson2_fixtures"
require_relative "page_world"
require "support/validation_servers"

# A lesson/2 of the student's page that holds a free page in an extra card (D-281): the body is the real parse of
# test/fixtures/lesson2/good/page-extra-card.md (invented content) with the pin resolved to a stored page revision, and the pages origin is a
# real server (the production mount of Banco::PagesApp on a free local port), so the iframe loads for real.
module PagesLessonWorld
  include Lesson2PageWorld
  include PageWorld

  EXTRA_CARD = 8

  # The pages origin of the test process: the production mount of Banco::PagesApp on a free local port, built once the port is known (its
  # CSP carries its own address). Started on first use, stopped with the run.
  class PagesOrigin
    class << self
      def port = (@server ||= start).connected_ports.first

      # The test driver adds the edge's Remote-User headers to every request of the browser, the iframe's too: a cross-origin module fetch
      # then needs a preflight, which production never sees (no such header there). The app answers OPTIONS with a 404 as it should; this
      # wrapper, which only the tests have, answers it so that the scripts load.
      def call(env)
        if env["REQUEST_METHOD"] == "OPTIONS"
          return [ 204, { "access-control-allow-origin" => "*", "access-control-allow-headers" => env["HTTP_ACCESS_CONTROL_REQUEST_HEADERS"].to_s, "access-control-allow-methods" => "GET" }, [] ]
        end

        (@app ||= Banco::PagesApp.new(mode: :production, origin: "http://127.0.0.1:#{port}", parent: Pages.app_origin)).call(env)
      end

      private

      def start
        server = Puma::Server.new(method(:call), nil, { min_threads: 0, max_threads: 6, log_writer: Puma::LogWriter.strings })
        server.add_tcp_listener("127.0.0.1", 0)
        server.run
        Minitest.after_run { server.stop(true) rescue nil }
        server
      end
    end
  end

  # Points the app at the pages origin and switches the pages on; returns the origin.
  def start_pages_origin!
    ENV["BANCO_PAGES_ORIGIN"] = "http://127.0.0.1:#{PagesOrigin.port}"
    ENV["BANCO_PAGES_ENABLED"] = "1"
    ENV["BANCO_PAGES_ORIGIN"]
  end

  def stop_pages_origin!
    ENV.delete("BANCO_PAGES_ORIGIN")
    ENV.delete("BANCO_PAGES_ENABLED")
  end

  # The page-extra-card lesson with its pin on +page_revision+, as the app stores it.
  def pages_lesson_body(page_revision)
    md = Lesson2Fixtures.read("good/page-extra-card.md").sub("revision: latest", "revision: #{page_revision.id}")
    outcome = Lesson2Fixtures.check(md, "math")
    raise "the gallery lesson has errors: #{outcome.findings.errors.map(&:message).inspect}" if outcome.findings.any_error?

    outcome.body.merge("key" => TOPIC)
  end

  def build_pages_lesson_world(page_revision, **options)
    @page_revision = page_revision
    build_student_world(**options)
  end

  def lesson_body = @page_revision ? pages_lesson_body(@page_revision) : super
end
