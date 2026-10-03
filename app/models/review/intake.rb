module Review
  # Checks a banco.review/1 document against the revision it reviews (A-05):
  # the schema, evidence that says something (E-REVIEW-EMPTY: a bare "all
  # verified" is refused) and quotes that are exact substrings of the item text
  # (E-QUOTE-NOT-FOUND). Returns Validation::Findings; nothing is stored here.
  module Intake
    module_function

    def call(doc, text)
      findings = Validation::Findings.new
      return findings unless Validation::SchemaCheck.call("review", doc, findings)

      weak, repeated = Checklist.empty_evidence(doc["checklist"])
      if weak.any?
        findings.add("E-REVIEW-EMPTY", "/checklist", "points #{weak.join(', ')} have no real evidence: say what you checked, on which instance (at least #{Checklist::MIN_WORDS} words, no stock phrase)", points: weak)
      end
      if repeated.any?
        findings.add("E-REVIEW-EMPTY", "/checklist", "the same evidence is used for more than one point: each point needs its own", rule: "repeated")
      end
      failed = doc["checklist"].select { |c| c["result"] == "fail" }.map { |c| c["id"] }
      findings.add("E-REVIEW-EMPTY", "/findings", "points #{failed.join(', ')} are marked fail but there is no finding: add a finding with a quote", points: failed) if failed.any? && doc["findings"].empty?

      doc["findings"].each_with_index do |f, i|
        if f.key?("instance") && text.instance_row(f["instance"]).nil?
          findings.add("E-QUOTE-NOT-FOUND", "/findings/#{i}/instance", "the review shows #{text.instances.size} instance(s); there is no instance #{f['instance']}", rule: "instance")
        elsif !text.quote?(f["quote"], instance: f["instance"])
          findings.add("E-QUOTE-NOT-FOUND", "/findings/#{i}/quote", "the quote is not an exact substring of the item text#{f.key?('instance') ? " or of instance #{f['instance']}" : ''}: copy it from banco review open", rule: "quote-#{i}", index: i)
        end
      end
      findings
    end
  end
end
