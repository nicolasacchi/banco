require "open3"

module Grading
  module Expression
    # One Node process running app/javascript/grader/worker.mjs, spoken to in JSON
    # lines: {"id":N,"op":...} out, {"id":N,"ok":true,"result":{...}} back. One
    # request at a time (a mutex); TIMEOUT seconds per request; a timeout, a crash or
    # a closed pipe kills the process, and the next request starts a fresh one.
    class Worker
      attr_reader :pid

      def initialize(node: ENV.fetch("BANCO_NODE", "node"), script: WORKER_SCRIPT)
        @node = node
        @script = script
        @mutex = Mutex.new
        @seq = 0
        @owner_pid = Process.pid
        @buffer = +""
        @stdin = @stdout = @wait = @pid = nil
      end

      # Sends one request and returns its "result" hash.
      def request(payload)
        @mutex.synchronize do
          ensure_running
          id = (@seq += 1)
          deadline = monotonic + TIMEOUT
          send_line(payload.merge("id" => id))
          loop do
            reply = JSON.parse(read_line(deadline))
            next unless reply["id"] == id # a late answer to an earlier request

            raise Unavailable, "worker error: #{reply['error']}" unless reply["ok"]

            return reply["result"]
          end
        rescue Unavailable
          kill
          raise
        rescue JSON::ParserError
          kill
          raise Unavailable, "worker sent something that is not JSON"
        end
      end

      def alive? = !@wait.nil? && @wait.alive?

      def stop
        @mutex.synchronize { kill }
      end

      # In a forked child: close the copies of the parent's pipes, leave the
      # parent's process alone.
      def abandon!
        [ @stdin, @stdout ].compact.each { |io| io.close unless io.closed? }
        @stdin = @stdout = @wait = nil
      end

      private

      def ensure_running
        return if alive?

        kill
        @buffer = +""
        @stdin, @stdout, @wait = Open3.popen2(@node, "--max-old-space-size=256", @script)
        @pid = @wait.pid
        ready = JSON.parse(read_line(monotonic + STARTUP_TIMEOUT))
        raise Unavailable, "worker did not announce readiness" unless ready["ready"]
      rescue SystemCallError => e
        kill
        raise Unavailable, "cannot start #{@node}: #{e.message}"
      rescue Unavailable
        kill
        raise
      end

      def send_line(hash)
        @stdin.write(JSON.generate(hash) << "\n")
        @stdin.flush
      rescue IOError, SystemCallError => e
        raise Unavailable, "worker pipe closed: #{e.class}"
      end

      def read_line(deadline)
        loop do
          if (newline = @buffer.index("\n"))
            return @buffer.slice!(0..newline)
          end

          remaining = deadline - monotonic
          raise TimedOut, "worker did not answer in time" if remaining <= 0
          raise TimedOut, "worker did not answer in time" unless IO.select([ @stdout ], nil, nil, remaining)

          chunk = @stdout.read_nonblock(65_536, exception: false)
          next if chunk == :wait_readable
          raise Unavailable, "worker closed its output" if chunk.nil?

          @buffer << chunk
        end
      rescue IOError, SystemCallError => e
        raise Unavailable, "worker pipe closed: #{e.class}"
      end

      def kill
        return unless @wait || @stdin

        Process.kill("KILL", @pid) if @pid && @wait&.alive? && @owner_pid == Process.pid
        [ @stdin, @stdout ].compact.each { |io| io.close unless io.closed? }
        @wait&.join(2)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      ensure
        @stdin = @stdout = @wait = nil
      end

      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
