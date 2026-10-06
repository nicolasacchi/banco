module Validation
  # `banco work submit --dry-run`: the same phases as the job, in the request, and
  # nothing kept: no item, no revision, no validation row, no instance, no queued job.
  # The files are staged in memory for the harness (the page of the run reads them by
  # a token that names the stage) and dropped after. Chrome is taken with a bounded wait
  # (BANCO_DRY_RUN_CHROME_WAIT seconds, default 25, so a dry run queues behind a short
  # validation): when it is still busy ChromeRunner::Busy is raised and the API answers
  # 409 E-CHROME-BUSY.
  module DryRun
    module_function

    CACHE_TTL = 600
    CACHE_MAX = 64
    CACHE = {}
    LOCK = Mutex.new

    # An identical dry run (same files, same course, same rules) within ten minutes is answered
    # from memory: the 200 seeds of a generator are not run again (D-160). Errors are never kept.
    def call(subject, files, verify_inherited: false)
      key = cache_key(subject, files, verify_inherited)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      hit = LOCK.synchronize { CACHE[key] }
      return hit[1] if hit && now - hit[0] < CACHE_TTL

      result = run(subject, files, verify_inherited)
      LOCK.synchronize do
        CACHE.delete(CACHE.keys.first) if CACHE.size >= CACHE_MAX
        CACHE[key] = [ now, result ]
      end
      result
    end

    def clear_cache = LOCK.synchronize { CACHE.clear }

    def cache_key(subject, files, verify_inherited)
      graphs = SkillGraphRevision.maximum(:id)
      refs = ReferenceText.maximum(:id)
      Digest::SHA256.hexdigest(JSON.generate([ subject.key, files.sort.to_h, verify_inherited, Rules.version, graphs, refs,
                                                SyllabusLine.maximum(:id), Decision.maximum(:id) ]))
    end

    def run(subject, files, verify_inherited)
      stage = Harness::Staging.put(files)
      ItemRunner.new(files: files, context: CourseContext.for(subject), harness_token: Harness.issue("stage", stage),
                     chrome: { wait: chrome_wait }, verify_inherited: verify_inherited).call
    ensure
      Harness::Staging.drop(stage) if stage
    end

    def chrome_wait = Float(ENV.fetch("BANCO_DRY_RUN_CHROME_WAIT", 25))
  end
end
