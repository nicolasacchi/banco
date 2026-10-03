require "test_helper"

class ProdSeedsTest < ActiveSupport::TestCase
  SEEDS = Rails.root.join("db/seeds.rb")
  SUBJECT_KEYS = %w[math italian english spanish history geography law_economics business
                    computer_science biology chemistry].freeze

  test "seeds create the eleven subjects with English keys, the two students and the Constitution" do
    load SEEDS
    assert_equal SUBJECT_KEYS.sort, Subject.pluck(:key).sort
    assert_equal %w[preview student], Student.pluck(:key).sort
    assert_equal "preview", Student.find_by!(key: "preview").kind
    text = ReferenceText.find_by!(key: "costituzione-artt-1-12")
    assert_equal Digest::SHA256.hexdigest(text.body), text.sha256
    assert_match %r{\Ahttps://}, text.source_url
    assert_equal 12, text.body.scan(/^## Art\. \d+$/).size
  end

  test "seeds create no decisions, approvals, attempts, runs, revisions or programmes" do
    load SEEDS
    [ Decision, Attempt, AttemptGrading, DiagnosisRun, DiagnosisEvent, ItemServed, SkillGraphRevision,
      BlueprintRevision, ItemRevision, ItemInstance, AgentSession, ApiToken, AppEvent, ItemReview, BlindSolve, ReviewFinding, GradeProposal,
      SyllabusSource, SyllabusLine ].each do |model|
      assert_equal 0, model.count, "#{model} must be empty after the production seeds"
    end
  end

  test "seeds are idempotent" do
    load SEEDS
    counts = [ Subject, Student, ReferenceText ].map(&:count)
    load SEEDS
    assert_equal counts, [ Subject, Student, ReferenceText ].map(&:count)
  end

  test "the Constitution file matches its recorded provenance" do
    provenance = YAML.safe_load_file(Rails.root.join("db/syllabus/costituzione-artt-1-12.source.yml"))
    body = Rails.root.join("db/syllabus/costituzione-artt-1-12.md").read
    assert_equal provenance.fetch("sha256"), Digest::SHA256.hexdigest(body)
  end

  test "no programme file is committed under db/syllabus" do
    names = Dir.children(Rails.root.join("db/syllabus"))
    assert names.none? { |name| name.match?(/programma/i) }, "programmes are imported from outside the repository"
  end
end
