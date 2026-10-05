# frozen_string_literal: true

module Validation
  # The validation of one item revision (A-06): schema and Ruby checks on item.json
  # and its files, instances (listed, or generated in Chrome), instance checks, the
  # grading round trip, and verify with its mutants. It returns a Result; it
  # persists nothing (the job and the dry run decide what to keep). Trouble with
  # Chrome or the grader worker is not a verdict: ChromeRunner::Unavailable,
  # ChromeRunner::Timeout, ChromeRunner::Busy and Roundtrip::Unavailable propagate.
  class ItemRunner
    Result = Struct.new(:status, :findings, :instances, :instances_sha256, :details, :chrome_version, keyword_init: true) do
      def passed? = status == "passed"
      def codes = findings.codes
    end

    GEN_BLOCKING = %w[E-GEN-THROW E-GEN-TIMEOUT E-GEN-SCHEMA E-GEN-NONDETERMINISTIC E-CODE-GLOBAL].freeze

    # files: {"item.json" => text, "generator.mjs" => text, ...}. harness_token:
    # what the harness serves the page with. chrome: options for ChromeRunner.session
    # (try: true for a dry run, which must not wait).
    def initialize(files:, context:, harness_token: nil, chrome: {})
      @files = files
      @context = context
      @token = harness_token
      @chrome = chrome
      @findings = Findings.new
      @details = {}
      @chrome_version = nil
      @first_error = nil
    end

    def call
      item = JSON.parse(@files.fetch("item.json"))
      keyed = display_key_scan(item)
      return finish(item, []) unless SchemaCheck.call("item", item, @findings, skip_extra_in_display: keyed) && !keyed

      ItemChecks.call(item, files: @files, context: @context, findings: @findings)
      instances = collect(item)
      finish(item, instances)
    end

    private

    def finish(_item, instances)
      @details[:rules_version] = Rules.version
      stored = instances.map { |i| i.merge(fingerprint: Canonical.fingerprint(i[:display])) }
      Result.new(status: @findings.any_error? ? "failed" : "passed", findings: @findings, instances: stored,
                 instances_sha256: stored.empty? ? nil : Digest::SHA256.hexdigest(Canonical.dump(stored.map { |i| i.slice(:display, :answer, :errors, :solution, :accept) })),
                 details: @details, chrome_version: @chrome_version)
    end

    # Listed instances whose display carries an answer-revealing field: E-DISPLAY-KEY at
    # once (the schema would only call it an extra member). True when any was found.
    def display_key_scan(item)
      found = false
      units = item["kind"] == "testlet" ? Array(item["sub_items"]).each_with_index.map { |s, i| [ s, "/sub_items/#{i}" ] } : [ [ item, "" ] ]
      units.each do |body, path|
        Array(body["instances"]).each_with_index do |inst, i|
          next unless inst.is_a?(Hash) && inst["display"].is_a?(Hash)

          Answers.display_keys(inst["display"]).each do |pointer, name|
            @findings.add("E-DISPLAY-KEY", "#{path}/instances/#{i}/display#{pointer}", "the display carries a field that reveals the answer (#{name})")
            found = true
          end
        end
      end
      found
    end

    # ---- instances by kind -------------------------------------------------------

    def collect(item)
      case item["kind"]
      when "short_answer" then [ short_answer_instance(item) ]
      when "testlet" then testlet(item)
      else single(item)
      end
    end

    def short_answer_instance(item)
      display = item["prompt"].slice("stem_it", "table", "quote", "figure")
      { seed: nil, display: display, answer: item["rubric"], errors: nil, solution: { "model_answer_it" => item.dig("rubric", "model_answer_it") } }
    end

    def single(item)
      unit = Units.of(item).first
      unit.generator ? generated(unit, item) : static(unit, item).tap { |list| verify_static(unit, item, list) }
    end

    def testlet(item)
      units = Units.of(item)
      lists = units.map do |unit|
        if unit.generator
          @findings.add("E-GEN-SCHEMA", "#{unit.path}/generator", "generators in testlet sub-items are not supported yet: list instances", rule: "testlet_generator")
          []
        else
          static(unit, item, passage: item["passage_it"])
        end
      end
      return [] if lists.any?(&:empty?)

      count = lists.map(&:size).min
      (0...count).map do |k|
        subs = units.each_with_index.map { |u, i| [ u, lists[i][k] ] }
        {
          seed: nil,
          display: { "passage_it" => item["passage_it"], "sub_items" => subs.map { |u, inst| { "id" => u.body["id"], "skill" => u.skill, "component" => u.component, "display" => inst[:display] } } },
          answer: subs.to_h { |u, inst| [ u.body["id"], inst[:answer] ] },
          errors: subs.to_h { |u, inst| [ u.body["id"], inst[:errors] ] },
          solution: subs.to_h { |u, inst| [ u.body["id"], inst[:solution] ] }
        }
      end
    end

    # ---- static items ------------------------------------------------------------------

    def static(unit, item, passage: nil)
      list = Array(unit.instances)
      checker = InstanceChecks.new(unit, context: @context, files: @files, passage: passage)
      list.each_with_index do |inst, i|
        @findings.merge!(checker.call(inst, label: "#{unit.path}/instances/#{i}"))
        ItemChecks.excluded_params(unit.body, inst, "#{unit.path}/instances/#{i}", @findings)
      end
      longest_correct(unit, list, checker)
      never_generated(unit, list)
      Roundtrip.new(unit, subject: item["subject"], findings: @findings).call(list, label: "#{unit.path}/instances", tests: unit.body["tests"])
      list.map { |i| stored_row(nil, i) }
    end

    # The row kept for an instance; accept (D-081) only when the instance has one, so the
    # hash of instances written before it does not change.
    def stored_row(seed, inst)
      row = { seed: seed, display: inst["display"], answer: inst["answer"], errors: inst["errors"], solution: inst["solution"] }
      row[:accept] = inst["accept"] if inst["accept"]
      row
    end

    def verify_static(unit, item, list)
      return unless @files.key?("verify.mjs") && list.any?

      with_chrome(generator: false) do |phase|
        state = phase.open_for_verify
        if !state["verify"]
          @findings.add("E-VERIFY-REJECTS", "/verify.mjs", state["verify_error"] || "verify.mjs does not load", rule: "load")
        else
          jobs = list.each_with_index.map { |inst, i| { id: "a#{i}", instance: inst[:display] && { "display" => inst[:display], "answer" => inst[:answer], "errors" => inst[:errors], "solution" => inst[:solution] } } }
          verdict = phase.verify(jobs)
          interpret_verify(unit, item, list.each_with_index.map { |inst, i| [ i, inst ] }, verdict, accept_prefix: "a", ids: :rejected_indexes)
        end
      end
    end

    # ---- generated items -----------------------------------------------------------------

    def generated(unit, item)
      return [] if @findings.include_code?("E-CODE-GLOBAL")

      with_chrome(generator: true) do |phase|
        gen = phase.generate_all(1..Rules.get(:generator, :seeds))
        return [] if generator_problems(gen)

        checker = InstanceChecks.new(unit, context: @context, files: @files)
        clean = []
        problems = 0
        gen.rows.each do |row|
          unless row.ok
            problems += 1
            @first_error ||= row.error
            next
          end
          if row.json.bytesize > Rules.get(:generator, :output_max_bytes)
            @findings.add("E-GEN-SCHEMA", "generated", "an output is over #{Rules.get(:generator, :output_max_bytes) / 1024} KB", rule: "size", seed: row.seed)
            problems += 1
            next
          end
          inst = row.output
          local = checker.call(inst, label: "generated", seed: row.seed, generated: true)
          merge_seed_findings(local)
          ItemChecks.excluded_params(unit.body, inst, "generated", @findings, seed: row.seed)
          if local.errors.empty?
            clean << { seed: row.seed, "display" => inst["display"], "answer" => inst["answer"], "errors" => inst["errors"], "solution" => inst["solution"], "accept" => inst["accept"] }
          else
            problems += 1
          end
        end
        pool_rules(unit, gen, clean, problems)
        stored = clean.first(Rules.get(:generator, :pool))
        generated_ok = clean.size >= Rules.get(:generator, :pool) && (@findings.codes & GEN_BLOCKING).empty?
        return [] unless generated_ok

        longest_correct(unit, stored.map { |c| c.transform_keys(&:to_s) }, checker)
        never_generated(unit, clean.map { |c| c.transform_keys(&:to_s) })
        Roundtrip.new(unit, subject: item["subject"], findings: @findings).call(stored.map { |c| c.transform_keys(&:to_s) }, label: "generated", tests: unit.body["tests"])
        verify_generated(unit, item, phase, gen, clean, stored)
        stored.map { |c| stored_row(c[:seed], c) }
      end
    end

    def merge_seed_findings(local)
      local.each do |f|
        @findings.add(f.code, f.field, f.message, **f.detail.except(:seeds, :count), seed: f.detail[:seeds]&.first)
      end
    end

    # Load errors, timeouts, throws and nondeterminism: true when nothing more can
    # be said about the generator.
    def generator_problems(gen)
      if gen.load_error
        @findings.add("E-GEN-THROW", "/generator.mjs", gen.load_error, rule: "load")
        return true
      end
      if gen.timed_out
        slow = gen.rows.last
        @findings.add("E-GEN-TIMEOUT", "/generator.mjs", "one generate call took #{slow.ms.round} ms (at most #{Rules.get(:generator, :generate_timeout_ms)})", seed: slow.seed)
        return true
      end
      if gen.nondeterministic.any?
        @findings.add("E-GEN-NONDETERMINISTIC", "/generator.mjs", "two fresh contexts gave a different output for the same seed", seed: gen.nondeterministic.first, count: gen.nondeterministic.size)
      end
      false
    end

    def pool_rules(unit, gen, clean, problems)
      total = gen.rows.size
      threw = gen.rows.count { |r| !r.ok }
      if total.positive? && threw.fdiv(total) > Rules.get(:generator, :max_problem_ratio)
        @findings.add("E-GEN-THROW", "/generator.mjs", "generate threw on #{threw} of #{total} seeds: #{@first_error}", count: threw)
      end
      pool = Rules.get(:generator, :pool)
      distinct = clean.first(pool).map { |c| Canonical.fingerprint(c["display"]) }.uniq.size
      @details.merge!(seeds: total, clean: clean.size, problem_seeds: problems, distinct_displays: distinct)
      if clean.size < pool
        @findings.add("E-GEN-POOL", "/generator.mjs", "only #{clean.size} clean seeds of #{total}; #{pool} are needed", clean: clean.size)
      elsif total.positive? && problems.fdiv(total) > Rules.get(:generator, :max_problem_ratio)
        @findings.add("E-GEN-POOL", "/generator.mjs", "#{problems} of #{total} seeds are problem seeds (at most #{(Rules.get(:generator, :max_problem_ratio) * 100).round}%)", problems: problems)
      elsif distinct < Rules.get(:generator, :min_distinct_displays)
        @findings.add("E-GEN-POOL", "/generator.mjs", "only #{distinct} distinct displays among #{pool}; #{Rules.get(:generator, :min_distinct_displays)} are needed", distinct: distinct)
      end
    end

    # ---- verify -------------------------------------------------------------------------------

    def verify_generated(unit, item, phase, gen, clean, stored)
      unless @files.key?("verify.mjs")
        @findings.add("E-VERIFY-MISSING", "/verify.mjs", "there is no verify.mjs yet: a verifier writes it from the instances", rule: "missing")
        return
      end
      unless gen.verify_loaded
        @findings.add("E-VERIFY-REJECTS", "/verify.mjs", gen.verify_error || "verify.mjs does not load", rule: "load")
        return
      end
      jobs = clean.map { |c| { id: "a#{c[:seed]}", instance: instance_for_verify(c) } }
      verdict = phase.verify(jobs)
      interpret_verify(unit, item, clean.map { |c| [ c[:seed], c ] }, verdict, accept_prefix: "a", stored_ids: stored.map { |c| c[:seed] })
      reject_jobs(unit, stored, phase)
    end

    def instance_for_verify(c)
      { "display" => c["display"], "answer" => c["answer"], "errors" => c["errors"], "solution" => c["solution"], "seed" => c[:seed] }.tap { |h| h["accept"] = c["accept"] if c["accept"] }
    end

    # Every rejected seed (or listed-instance index) is named, with the reason per seed
    # grouped by wording: a verifier sees the whole pool's trouble in one run.
    def interpret_verify(_unit, _item, rows, verdict, accept_prefix:, ids: :rejected_seeds, stored_ids: nil)
      @details[:verify] = { checked: rows.size }
      rejected = rows.select { |id, _| !verdict.dig("#{accept_prefix}#{id}", "ok") }
      @details[:verify][:rejected] = rejected.size
      return if rejected.empty?

      first = verdict["#{accept_prefix}#{rejected.first[0]}"]
      reasons = rejected.group_by { |id, _| (verdict["#{accept_prefix}#{id}"] || {}).values_at("reason", "reason_it").compact.first.to_s }
                        .to_h { |reason, list| [ reason, list.map(&:first) ] }
      @findings.add("E-VERIFY-REJECTS", "/verify.mjs", "verify rejects #{rejected.size} clean #{rejected.size == 1 ? 'instance' : 'instances'}#{": #{first['reason']}" if first && first['reason']}",
                    seed: rejected.first[0], count: rejected.size, ids => rejected.map(&:first), reasons: reasons,
                    first_rejected: first_rejected_instance(rejected.first[1]),
                    rejected_samples: rejected_samples(rejected, verdict, accept_prefix, stored_ids))
    end

    # Up to VERIFY_SAMPLES rejected instances with their reason, display and answer, and whether
    # the verifier was given that seed (work open lists only the stored pool; verify runs on
    # every clean seed), so one run shows several unseen cases, not one.
    VERIFY_SAMPLES = 8

    def rejected_samples(rejected, verdict, prefix, stored_ids)
      rejected.first(VERIFY_SAMPLES).map do |id, inst|
        v = verdict["#{prefix}#{id}"] || {}
        { "id" => id, "reason" => v.values_at("reason", "reason_it").compact.first, "in_stored_pool" => stored_ids ? stored_ids.include?(id) : nil }
          .merge(first_rejected_instance(inst) || {}).compact
      end
    end

    # The first rejected instance as the verifier saw it (display and answer, clipped), so
    # a seed number outside the listed samples can be debugged without guessing.
    def first_rejected_instance(inst)
      return nil unless inst.respond_to?(:[]) && !inst.is_a?(String)

      { "display" => inst["display"], "answer" => inst["answer"] }.compact.transform_values do |v|
        json = v.is_a?(String) ? v : JSON.generate(v)
        json.length > 400 ? "#{json[0, 400]}..." : v
      end
    end

    # Error values and the +1 and sign-flip mutants must all be rejected.
    def reject_jobs(unit, stored, phase)
      jobs = []
      stored.first(Rules.get(:generator, :verify_instances)).each do |c|
        Array(c["errors"]).each_with_index do |e, i|
          jobs << { id: "e#{c[:seed]}:#{i}", instance: instance_for_verify(c).merge("answer" => e["value"]), label: "the error value of #{e['code']}" }
        end
        next unless %w[number fraction].include?(unit.component)

        { "p" => ->(r) { r + 1 }, "s" => ->(r) { -r } }.each do |prefix, fn|
          mutated = mutate(c["answer"], fn)
          jobs << { id: "#{prefix}#{c[:seed]}", instance: instance_for_verify(c).merge("answer" => mutated), label: prefix == "p" ? "the +1 mutant" : "the sign-flip mutant" } if mutated
        end
      end
      return if jobs.empty?

      verdict = phase.verify(jobs.map { |j| j.slice(:id, :instance) })
      accepted = jobs.select { |j| verdict.dig(j[:id], "ok") }
      return if accepted.empty?

      @findings.add("E-VERIFY-VACUOUS", "/verify.mjs", "verify accepts #{accepted.first[:label]} (#{accepted.size} wrong #{accepted.size == 1 ? 'answer' : 'answers'} accepted)",
                    seed: accepted.first[:id][/\d+/].to_i, count: accepted.size)
    end

    # The key moved by +1 or flipped, in the same style as the key.
    def mutate(answer, fn)
      value = answer.is_a?(Hash) ? Answers.rational("n" => answer["n"], "d" => answer["d"]) : Answers.rational(answer)
      return nil unless value

      mutated = fn.call(value)
      return nil if mutated == value

      case answer
      when Integer then mutated.denominator == 1 ? mutated.to_i : nil
      when Float then mutated.to_f
      when Hash then { "n" => mutated.numerator, "d" => mutated.denominator }
      else Answers.decimal_string(mutated) || "#{mutated.numerator}/#{mutated.denominator}"
      end
    end

    # ---- cross-instance rules --------------------------------------------------------------------

    def longest_correct(unit, list, checker)
      return unless unit.component == "choice"
      return if list.size < Rules.get(:pool, :longest_correct_min_instances)

      share = list.count { |i| checker.longest_correct?(i) }.fdiv(list.size)
      return unless share > Rules.get(:pool, :longest_correct_ratio)

      @findings.add("W-LONGEST-CORRECT", "#{unit.path}/display/options", "the correct option is the longest in #{(share * 100).round}% of the instances")
    end

    def never_generated(unit, list)
      seen = list.flat_map { |i| Array(i["errors"]).map { |e| e["code"] } }.uniq
      (unit.catalogue_codes - seen).each do |code|
        @findings.add("E-ERROR-NEVER-GENERATED", "#{unit.path}/error_catalogue", "the catalogue error #{code} is never produced by any instance", code: code)
      end
    end

    # ---- Chrome ---------------------------------------------------------------------------------------

    def with_chrome(generator:)
      raise ArgumentError, "no harness token" unless @token

      ChromeRunner.session(**@chrome) do |session|
        @chrome_version = session.version
        phase = ChromePhase.new(session, token: @token, generator: generator, verify: @files.key?("verify.mjs"))
        begin
          yield phase
        ensure
          phase.close
        end
      end
    end
  end
end
