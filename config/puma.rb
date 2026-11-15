# One Puma, single mode, five listeners (D-04):
#   WEB_PORT     3000  HTML for the student and the teacher; reached only by Traefik
#   API_PORT     3100  agent API, published on 127.0.0.1 only; token auth
#   HARNESS_PORT 3200  internal harness for Chrome; never published
#   PAGES_PORT   3300  the free pages origin (release 2, D-290); reached only by Traefik on banco-edge, not published
#   VIEW_PORT    3400  view links (D-332): GET only, a temporary URL opens the teacher's pages read-only; reached only by Traefik
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

# No body over 10 MB is read, before any token is looked at (D-327: the API listener is public). The largest real submit is a page
# bundle (3 MB, Api::V1::PagesController::MAX_BODY; an item's files are at most 2 MB).
http_content_length_limit 10 * 1024 * 1024
