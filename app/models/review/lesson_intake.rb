module Review
  # Checks a banco.lesson_review/1 document against the lesson revision it reviews (A2.5): the schema, evidence
  # that says something (E-REVIEW-EMPTY), quotes that are exact substrings of lesson.md (E-QUOTE-NOT-FOUND), and,
  # for math, the recomputed exercises (E-LESSON-REVIEW-RECOMPUTED). Returns Validation::Findings; nothing is stored.
  module LessonIntake
    module_function

    def call(doc, revision)
      findings = Validation::Findings.new
      return findings unless Validation::SchemaCheck.call("lesson_review", doc, findings)

      weak, repeated = Checklist.empty_evidence(doc["checklist"])
      if weak.any?
        findings.add("E-REVIEW-EMPTY", "/checklist", "points #{weak.join(', ')} have no real evidence: say what you checked, on which exercise, in at least #{Checklist::MIN_WORDS} words and not a stock phrase", points: weak)
      end
      findings.add("E-REVIEW-EMPTY", "/checklist", "the same evidence is used for more than one point: each point needs its own", rule: "repeated") if repeated.any?
      failed = doc["checklist"].select { |c| c["result"] == "fail" }.map { |c| c["id"] }
      findings.add("E-REVIEW-EMPTY", "/findings", "points #{failed.join(', ')} are marked fail but there is no finding: add a finding with a quote", points: failed) if failed.any? && doc["findings"].empty?

      doc["findings"].each_with_index do |f, i|
        next if revision.source_md.include?(f["quote"])

        findings.add("E-QUOTE-NOT-FOUND", "/findings/#{i}/quote", "the quote is not an exact substring of lesson.md: copy it from banco lesson-review open", rule: "quote-#{i}", index: i)
      end
      recomputed(doc, revision, findings)
      findings
    end

    # Math: at least lesson.review_min_recomputed_math entries and one for every exercise that has a final.
    def recomputed(doc, revision, findings)
      body = revision.body
      return unless body["subject"] == "math"

      min = Validation::Rules.get(:lesson, :review_min_recomputed_math)
      if doc["recomputed"].size < min
        findings.add("E-LESSON-REVIEW-RECOMPUTED", "/recomputed", "a math lesson needs at least #{min} recomputed values; there are #{doc['recomputed'].size}", rule: "count", count: doc["recomputed"].size)
      end
      done = doc["recomputed"].filter_map { |r| r["n"] }.to_set
      missing = body["exercises"].select { |e| !e["final_it"].nil? && !done.include?(e["n"]) }.map { |e| e["n"] }
      findings.add("E-LESSON-REVIEW-RECOMPUTED", "/recomputed", "exercise(s) #{missing.join(', ')} have a final answer but no recomputed entry with that n", rule: "exercises", exercises: missing) if missing.any?
    end
  end
end
