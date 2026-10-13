namespace :banco do
  desc "Store the browser matrix page math.pages-selftest as an unpinned revision (D-289, SPEC B10.8). Operator's console only; dry run unless CONFIRM=1."
  task pages_selftest: :environment do
    dir = Rails.root.join("test/fixtures/pages/math.pages-selftest")
    files = Dir.glob("**/*", base: dir.to_s).select { |f| File.file?(dir.join(f)) }.to_h { |f| [ f, File.binread(dir.join(f)) ] }
    subject = Subject.find_by(key: "math") or abort "banco:pages_selftest: no subject math"
    outcome = Validation::PageChecks.call(files, key: "math.pages-selftest", subject: "math", scan: false, operator: true)
    abort "banco:pages_selftest: #{outcome.findings.errors.map(&:message).first(3).join('; ')}" if outcome.findings.any_error?

    if ENV["CONFIRM"] == "1"
      revision, replayed = Pages::Submit.store(key: "math.pages-selftest", subject: subject, outcome: outcome, warnings: [], author: nil, operator: true)
      puts JSON.generate(page: "math.pages-selftest", revision_id: revision&.id, replayed: replayed, bundle_sha256: outcome.bundle_sha256, next: "open /teacher/pages/selftest")
    else
      puts JSON.generate(dry_run: true, bundle_sha256: outcome.bundle_sha256, next: "CONFIRM=1 bin/rails banco:pages_selftest")
    end
  end
end
