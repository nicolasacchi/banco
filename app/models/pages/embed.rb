# The lookup behind the lesson's `page` block (SPEC B4, D-281): does the page revision exist, belong to the lesson's subject and
# have passed validation. `latest` is the page's newest revision. Returns { revision_id:, problem:, strings: }: problem is nil
# when the pin is good; strings are the text constants of the page's modules, for the leak scan (W-PAGE-KEY).
module Pages
  module Embed
    module_function

    def lookup(subject, key, revision)
      page = Page.find_by(key: key)
      return { revision_id: nil, problem: "no page #{key}: submit it first (banco page submit DIR), then embed a revision that passed validation" } unless page
      return { revision_id: nil, problem: "the page #{key} belongs to #{page.subject.key}, not to #{subject.key}" } unless page.subject_id == subject.id

      rev = revision == "latest" ? page.latest_revision : page.revisions.find { |r| r.id == revision }
      return { revision_id: nil, problem: "page #{key} has no revision #{revision}" } unless rev

      problem = if rev.passed_validation.nil?
        verdict = rev.verdict
        verdict ? "revision #{rev.id} of #{key} did not pass validation (banco page status #{rev.id})" : "revision #{rev.id} of #{key} has not been validated yet (banco page status #{rev.id})"
      end
      { revision_id: rev.id, problem: problem, strings: strings_of(rev), instructions: JSON.parse(rev.manifest_json)["instructions_it"] }
    end

    # Every string literal of the page's modules (comments and the rest blanked by the lexer).
    def strings_of(revision)
      revision.files.select { |f| f.path.end_with?(".mjs") }.flat_map do |f|
        Validation::JsScan.lex(Pages::Store.read(f.sha256).to_s.dup.force_encoding("UTF-8").scrub).strings
      end.uniq
    end
  end
end
