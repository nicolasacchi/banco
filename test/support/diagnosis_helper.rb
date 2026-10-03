# Builders and a driver for the pure diagnosis engine tests: a tiny way to say
# "this graph, these entries, these items" and to play a student one answer at a
# time on a fake clock. No database.
module DiagnosisHelper
  # skills: {"math.a" => {prereqs: [], errors: {"code" => ["math.b"]}, scope: "studied",
  #                       composite_of: [], subject: nil}}
  # entries: skill keys in order (default: the first skill).
  # items: {"math.a" => ["a1", "a2"]} item ids of an entry (default two items).
  # pool: {"a1" => {"component" => "choice", "instances" => 2, ...}} overrides.
  def build_plan(skills:, entries: nil, items: {}, pool: {}, minutes: 30, sittings: 2, choice_only: [], external: {},
                 seen: [], salt: "test", overrides: [], guests: {}, subject: "math")
    entries ||= [ skills.keys.first ]
    blueprint = {
      "subject" => subject,
      "entries" => entries.map do |k|
        e = { "skill" => k, "items" => items.fetch(k) { %W[#{k}-i1 #{k}-i2] } }
        e["choice_only_reason_it"] = "scelta" if choice_only.include?(k)
        e["guest_of_subject"] = guests[k] if guests[k]
        e
      end,
      "budget" => { "sitting_minutes" => minutes, "sittings" => sittings },
      "kind_overrides" => overrides
    }
    graph = {
      "skills" => skills.map do |k, s|
        { "key" => k, "scope" => s.fetch(:scope, "studied"), "prerequisites" => s.fetch(:prereqs, []),
          "composite_of" => s.fetch(:composite_of, []),
          "errors" => s.fetch(:errors, {}).map { |code, imp| { "code" => code, "implicates" => imp } } }
      end
    }
    Diagnosis::Plan.build(blueprint: blueprint, graph: graph, pool: pool, external: external, seen: seen, seed_salt: salt)
  end

  # A plan is a Data; the pool can be replaced to add a short answer or a testlet.
  def with_instances(plan, extra)
    pool = plan.pool.values + extra
    Diagnosis::Plan.new(subject: plan.subject, entries: plan.entries, skills: plan.skills, pool: pool.to_h { |i| [ i.id, i ] },
                        sitting_seconds: plan.sitting_seconds, sittings: plan.sittings, seed_salt: plan.seed_salt,
                        external: plan.external, seen: plan.seen)
  end

  def instance(id, skills:, kind: "diagnosis_item", component: "number", low_guess: nil, choice: nil, seconds: 60, item: nil)
    low_guess = Diagnosis::Rules::V1.low_guess?(component) if low_guess.nil?
    choice = component == "choice" if choice.nil?
    Diagnosis::Plan::Instance.new(id: id, item: item || id, skills: Array(skills), component: component, low_guess: low_guess,
                                  choice: choice, expected_seconds: seconds, fingerprint: Digest::SHA256.hexdigest(id), kind: kind)
  end

  # Plays a student against the engine, one step at a time.
  class Driver
    attr_reader :plan, :events, :clock

    def initialize(plan, clock: Diagnosis::FakeClock.new)
      @plan = plan
      @clock = clock
      @events = []
    end

    def push(kind, **payload)
      @events << { kind: kind, at: clock.now, seq: @events.size + 1 }.merge(payload)
      @events.last
    end

    def action = Diagnosis::Engine.next_action(plan, events, clock)

    def start = push("sitting_started")

    # Serve what the engine says; returns the serve event.
    def serve!
      a = action
      raise "expected :serve, engine said #{a.type} #{a.reason}" unless a.type == :serve

      push("item_served", instance: a.instance.id, skill: a.skill)
    end

    def answer(serve, verdict, seconds: 30, **ctx)
      clock.advance(seconds)
      push("answered", serve: serve[:seq], verdict: verdict, **ctx)
    end

    # Serve and answer; returns the action that was served.
    def play(verdict, seconds: 30, **ctx)
      a = action
      s = serve!
      answer(s, verdict, seconds: seconds, **ctx)
      a
    end

    def next_skill = action.skill

    def result = Diagnosis::Derivation.result(plan, events)

    def state(skill)
      row = result[:skills].find { |r| r[:skill] == skill }
      [ row[:state], row[:reason] ]
    end

    def end_reason = result[:end_reason]

    # Engine closes the run as it would in the app.
    def finish!
      loop do
        a = action
        case a.type
        when :close_run then return push("run_closed", reason: a.reason)
        when :end_sitting then push("sitting_closed", reason: a.reason)
        when :start_sitting
          clock.advance_to(a.not_before)
          push("sitting_started")
        else return a
        end
      end
    end
  end
end
