# frozen_string_literal: true

require "set"

module Practice
  # Skill states from tries (A8.5), pure. The fold replays each skill's tries in time order, starting
  # from the diagnosis seed (or not_seen), so the same rows always give the same states.
  #
  #   Practice::Fold.call(seeds: {skill => Seed}, tries: [Try]) # => {skill => SkillState}
  #
  # serves: and skills: are optional: ServeRows add the serve, hint, solution and abandoned counts and the
  # serves with no try (a fingerprint counts as served from its first serve); skills: names skills to
  # report as not_seen when nothing is known of them.
  module Fold
    V1 = Rules::V1
    DAY = 86_400

    Machine = Struct.new(:state, :previous, :since, :demonstrated_at, :demonstrated_day, :consolidated_at, :consolidated_day,
                         :review_day, :fingerprints, :days, :review_fingerprints, keyword_init: true)

    module_function

    def call(seeds:, tries:, serves: [], skills: [])
      by_skill = tries.group_by(&:skill)
      serves_by = serves.group_by(&:skill)
      first_serve = first_serves(tries, serves)
      keys = (seeds.keys + by_skill.keys + serves_by.keys + skills).uniq
      keys.to_h { |k| [ k, skill_state(k, seeds[k], by_skill.fetch(k, []), serves_by.fetch(k, []), first_serve) ] }
    end

    # {fingerprint => the lowest serve id that showed it}
    def first_serves(tries, serves)
      out = {}
      tries.each { |t| out[t.fingerprint] = [ out[t.fingerprint], t.serve_id ].compact.min }
      serves.each { |s| out[s.fingerprint] = [ out[s.fingerprint], s.id ].compact.min }
      out
    end

    def skill_state(skill, seed, tries, serves, first_serve)
      m = Machine.new(state: seed ? seed.state.to_s : "not_seen", since: seed&.at, fingerprints: {}, days: Set.new, review_fingerprints: Set.new)
      m.demonstrated_at = seed.at if seed&.state.to_s == "demonstrated"
      m.demonstrated_day = seed.at.to_date if m.demonstrated_at
      sorted = tries.sort_by { |t| [ t.at, t.serve_id, t.try_number ] }
      sorted.each { |t| step(m, t, first_serve) }
      SkillState.new(skill: skill, state: m.state, since: m.since, demonstrated_at: m.demonstrated_at, consolidated_at: m.consolidated_at,
                     seed: seed, counts: counts(sorted, serves), why: why(m, seed))
    end

    def step(m, try, first_serve)
      aided = try.aided || try.reseen
      credit = try.evidence == :C && !aided
      if %w[not_seen to_recover to_learn].include?(m.state)
        m.state = "in_study"
        m.since = try.at
      end
      case m.state
      when "in_study" then in_study(m, try, credit)
      when "demonstrated" then demonstrated(m, try, credit, aided, first_serve)
      when "consolidated" then to_review(m, try) if try.evidence == :W && !aided
      when "to_review" then in_review(m, try, credit)
      end
    end

    def in_study(m, try, credit)
      return unless credit

      m.fingerprints[try.fingerprint] ||= try.low_guess
      m.days << try.day
      return unless m.fingerprints.size >= V1::DEMONSTRATE_CORRECT_UNAIDED && m.days.size >= V1::DEMONSTRATE_DISTINCT_DAYS &&
                    m.fingerprints.values.count(true) >= V1::DEMONSTRATE_MIN_LOW_GUESS

      m.state = "demonstrated"
      m.since = m.demonstrated_at = try.at
      m.demonstrated_day = try.day
    end

    def demonstrated(m, try, credit, aided, first_serve)
      if credit && first_serve[try.fingerprint] == try.serve_id && try.at - m.demonstrated_at >= V1::CONSOLIDATE_AFTER_DAYS * DAY
        m.state = "consolidated"
        m.since = m.consolidated_at = try.at
        m.consolidated_day = try.day
      elsif try.evidence == :W && !aided
        to_review(m, try)
      end
    end

    def to_review(m, try)
      m.previous = m.state
      m.state = "to_review"
      m.since = try.at
      m.review_day = try.day
      m.review_fingerprints = Set.new
    end

    def in_review(m, try, credit)
      return unless credit

      m.review_fingerprints << try.fingerprint
      return if m.review_fingerprints.size < V1::REVIEW_BACK_CORRECT

      m.state = m.previous
      m.since = try.at
      m.previous = nil
    end

    def counts(tries, serves)
      c = { serves: (tries.map(&:serve_id) + serves.map(&:id)).uniq.size, tries: tries.size,
            correct_unaided: 0, correct_aided: 0, wrong: 0, typical: Hash.new(0), unrecognised: 0, near_miss: 0, undetermined: 0,
            hints: serves.sum(&:hints_shown), solutions_requested: serves.count(&:solution_requested),
            abandoned: serves.count { |s| s.status.state == :abandoned }, seconds: tries.sum { |t| [ t.seconds.to_i, V1::TIME_CAP_SECONDS ].min } }
      tries.each do |t|
        c[:wrong] += 1 if t.evidence == :W
        case t.outcome
        when :correct then c[:correct_unaided] += 1
        when :correct_aided then c[:correct_aided] += 1
        when :typical_error then c[:typical][t.error_codes.first || "unknown"] += 1
        when :unrecognised then c[:unrecognised] += 1
        when :near_miss then c[:near_miss] += 1
        when :undetermined then c[:undetermined] += 1
        end
      end
      c[:typical] = c[:typical].to_h
      c
    end

    # A code and its parameters; Practice::Messages turns it into a sentence of the student.
    def why(m, seed)
      case m.state
      when "in_study"
        { code: :in_study, n: [ m.fingerprints.size, V1::DEMONSTRATE_CORRECT_UNAIDED ].min, d: [ m.days.size, V1::DEMONSTRATE_DISTINCT_DAYS ].min }
      when "demonstrated"
        if m.fingerprints.empty? && seed&.state.to_s == "demonstrated"
          { code: seed.implied ? :seed_implied : :seed_demonstrated, date: m.demonstrated_day }
        else
          { code: :demonstrated, date: m.demonstrated_day, days: m.days.size }
        end
      when "consolidated" then { code: :consolidated, date: m.consolidated_day }
      when "to_review" then { code: :to_review, date: m.review_day, previous: m.previous }
      when "to_recover" then { code: :seed_to_recover }
      when "to_learn" then { code: :seed_to_learn }
      else { code: :not_seen }
      end
    end
  end
end
