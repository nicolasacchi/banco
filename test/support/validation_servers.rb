require "puma"
require "puma/server"

# Real listeners for tests that need an HTTP client: Chrome loading the harness,
# the compiled CLI calling the API. Each is a Puma::Server on a free local port,
# wrapped so that every request carries the listener tag through the test seam
# (env["banco.test_listener"], honoured only in the test environment). Started once
# per test process; the test's pinned database connection is shared with the server
# threads (Rails' lock_threads), so rows created by a test are visible to them.
module ValidationServers
  Handle = Struct.new(:server, :thread, :port, keyword_init: true)

  @handles = {}
  @mutex = Mutex.new

  class << self
    # The port of the listener (:api or :harness), starting it on first use.
    def port(name)
      handle(name).port
    end

    def url(name) = "http://127.0.0.1:#{port(name)}"

    # Points the harness base URL at the running harness listener.
    def harness!
      ENV["BANCO_HARNESS_URL"] = url(:harness)
    end

    def stop_all
      @mutex.synchronize do
        @handles.each_value { |h| h.server.stop(true) rescue nil }
        @handles.clear
      end
    end

    private

    def handle(name)
      @mutex.synchronize { @handles[name] ||= start(name) }
    end

    def start(name)
      rails = lambda do |env|
        env["banco.test_listener"] = name.to_s
        Rails.application.call(env)
      end
      # The harness listener also carries the validation mount of the pages app under Host: banco-pages-internal (D-281), built on
      # the first request, when BANCO_HARNESS_URL names this server.
      validation = nil
      mount = ->(env) { (validation ||= Banco::PagesApp.new(mode: :validate, origin: Pages.validation_origin, parent: Pages.validation_parent)).call(env) }
      switch = Banco::ListenerSwitch.new(rails, production: mount, validation: mount, allow_test_seam: true)
      app = lambda do |env|
        env["banco.test_listener"] = name.to_s
        switch.call(env)
      end
      server = Puma::Server.new(app, nil, { min_threads: 0, max_threads: 6, log_writer: Puma::LogWriter.strings })
      server.add_tcp_listener("127.0.0.1", 0)
      thread = server.run
      Handle.new(server: server, thread: thread, port: server.connected_ports.first)
    end
  end
end

Minitest.after_run { ValidationServers.stop_all }
