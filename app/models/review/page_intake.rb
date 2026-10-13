module Review
  # Checks a banco.page_review/1 document against the page revision it reviews (SPEC B8): the schema, the evidence of the
  # eleven points, and every finding naming a file of the revision and quoting it exactly. Returns Validation::Findings;
  # nothing is stored.
  module PageIntake
    module_function

    def call(doc, revision)
      findings = Validation::Findings.new
      return findings unless Validation::SchemaCheck.call("page_review", doc, findings)

      weak, repeated = Checklist.empty_evidence(doc["checklist"])
      findings.add("E-REVIEW-EMPTY", "/checklist", "points #{weak.join(', ')} have no real evidence: say what you checked, in at least #{Checklist::MIN_WORDS} words and not a stock phrase", points: weak) if weak.any?
      findings.add("E-REVIEW-EMPTY", "/checklist", "the same evidence is used for more than one point: each point needs its own", rule: "repeated") if repeated.any?
      failed = doc["checklist"].select { |c| c["result"] == "fail" }.map { |c| c["id"] }
      findings.add("E-REVIEW-EMPTY", "/findings", "points #{failed.join(', ')} are marked fail but there is no finding: add a finding with a quote", points: failed) if failed.any? && doc["findings"].empty?

      texts = texts_of(revision)
      doc["findings"].each_with_index do |f, i|
        text = texts[f["file"]]
        if text.nil?
          findings.add("E-QUOTE-NOT-FOUND", "/findings/#{i}/file", "#{f['file']} is not a text file of the revision (#{texts.keys.join(', ')})", rule: "file-#{i}", index: i)
        elsif !text.include?(f["quote"])
          findings.add("E-QUOTE-NOT-FOUND", "/findings/#{i}/quote", "the quote is not an exact substring of #{f['file']}: copy it from banco page-review open", rule: "quote-#{i}", index: i)
        end
      end
      findings
    end

    # The text files of a revision by path, page.json included (pretty-printed as `page-review open` shows it).
    def texts_of(revision)
      out = { "page.json" => JSON.pretty_generate(revision.manifest) }
      revision.files.each do |f|
        next unless f.path.match?(/\.(mjs|css|svg)\z/)

        out[f.path] = Pages::Store.read(f.sha256).to_s.dup.force_encoding("UTF-8").scrub
      end
      out
    end
  end
end
