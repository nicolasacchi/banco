# One Puma, single mode, three listeners (D-04):
#   WEB_PORT     3000  HTML for the student and the teacher; reached only by Traefik
#   API_PORT     3100  agent API, published on 127.0.0.1 only; token auth
#   HARNESS_PORT 3200  internal harness for Chrome; never published
# The variables are deliberately not called PORT.
require_relative "../lib/banco/listeners"

threads_count = Integer(ENV.fetch("RAILS_MAX_THREADS", 5))
threads threads_count, threads_count

ports = Banco::Listeners.assert_distinct!
bind_host = ENV.fetch("BANCO_BIND_HOST", "0.0.0.0")
ports.each_value { |port| bind "tcp://#{bind_host}:#{port}" }

plugin :tmp_restart

# Solid Queue supervisor inside Puma (single mode).
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
