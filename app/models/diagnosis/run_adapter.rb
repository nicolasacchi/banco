module Diagnosis
  # One diagnosis run seen through the pure engine: loads the plan and the events
  # with the loaders and calls the fold. The only place where rows meet the
  # engine; it writes nothing (the caller appends the event that goes with an
  # action, in its own transaction).
  class RunAdapter
    attr_reader :run

    def initialize(run)
      @run = run
    end

    def plan = @plan ||= PlanLoader.for_run(run)
    def events = @events ||= EventLoader.for_run(run)
    def voided? = @voided ||= EventLoader.voided?(run)

    # States of every skill, the time account and the end reason (B-04, B-05).
    def result = Derivation.result(plan, events, voided: voided?)

    # What the engine wants done next, as an Engine::Action.
    def next_action(clock = Clock.new) = Engine.next_action(plan, events, clock)
  end
end
