# frozen_string_literal: true

require "set"

module Diagnosis
  # The result of folding a log: everything the engine knows after the last event.
  # Built by Fold; read by Engine (next action) and Derivation (states). Mutated
  # only while folding.
  class State
    # One item put in front of the student. answers: {skill => Answer}.
    Serve = Struct.new(:seq, :instance, :at, :sitting, :answered_at, :abandoned_at, :answers, keyword_init: true) do
      def open? = answered_at.nil? && abandoned_at.nil?
      def stop_at = answered_at || abandoned_at
    end

    # What the engine knows about one answer on one skill. evidence: :C :W :D
    # :pending :ungraded. counted: it became an outcome of the skill.
    Answer = Struct.new(:evidence, :verdict, :retry_state, :counted, keyword_init: true) do
      # Why an uncounted answer is pending (B-04).
      def pending_reason
        return "grade_unconfirmed" if verdict == "short_answer"
        return "verdict_pending" if evidence == :pending
        return "verdict_pending" if retry_state.to_s == "exhausted"

        "grader_unavailable"
      end
    end

    Sitting = Struct.new(:index, :started_at, :closed_at, :close_reason, :serve_seqs, keyword_init: true)

    attr_reader :plan, :outcomes, :serves, :sittings, :frontier, :stalled, :origin, :observations, :suspect_log,
                :served_count, :outstanding, :below, :visited, :pauses, :hiddens, :served_fingerprints
    attr_accessor :closed, :end_reason, :extends, :short_serve, :short_state, :last_close_reason

    def initialize(plan)
      @plan = plan
      @outcomes = {}
      @serves = []
      @serve_by_seq = {}
      @sittings = []
      @frontier = []
      @stalled = {}
      @origin = {}
      @observations = []
      @suspect_log = []
      @served_count = Hash.new(0)
      @outstanding = Hash.new { |h, k| h[k] = Set.new }
      @below = Set.new
      @visited = Set.new
      @pauses = []
      @hiddens = []
      @served_fingerprints = Set.new
      @closed = false
      @end_reason = nil
      @extends = 0
      @short_serve = nil
      @short_state = nil
      @last_close_reason = nil
    end

    def serve(seq) = @serve_by_seq[seq]

    def add_serve(serve)
      @serves << serve
      @serve_by_seq[serve.seq] = serve
    end

    def current_sitting = @sittings.last
    def open_sitting = @sittings.last && !@sittings.last.closed_at ? @sittings.last : nil
    def open_serve = @serves.last&.open? ? @serves.last : nil

    def allowed_sittings
      (Rules::V1::AUTO_SECOND_SITTING ? @plan.sittings : 1) + @extends
    end

    # Own outcome of a skill, if any.
    def outcome(key) = @outcomes[key]

    # [state, reason, source] for a skill that is resolved here or reused from
    # another run; nil otherwise.
    def resolved_state(key)
      own = @outcomes[key]
      return [ own.state, own.reason, "run" ] if own&.resolved?
      return [ @short_state[0], @short_state[1], "run" ] if key == @plan.short_skill && @short_state

      ext = @plan.external[key]
      return [ ext["state"], ext["reason"], "cross_subject" ] if ext && %w[demonstrated to_recover].include?(ext["state"]) && !own_active?(key)

      nil
    end

    def demonstrated?(key) = resolved_state(key)&.first == "demonstrated"

    # A skill of this run that has been served at least once is judged on its
    # own items, so an older result elsewhere does not replace it.
    def own_active?(key) = @served_count[key].positive?

    # Counted seconds of every finished item of a sitting.
    def sitting_counted_seconds(sitting)
      sitting.serve_seqs.sum { |seq| serve_counted_seconds(@serve_by_seq[seq]) }
    end

    def serve_counted_seconds(serve)
      stop = serve.stop_at
      return 0 unless stop

      TimeAccount.counted_seconds(serve.at, stop, @pauses + @hiddens, testlet: serve.instance.testlet?)
    end

    def counted_seconds_total = @sittings.sum { |s| sitting_counted_seconds(s) }
  end
end
