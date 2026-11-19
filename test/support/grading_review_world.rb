require_relative "practice_text_world"

# A world for «Contestazioni» (D-368, Teacher::GradingReview): the official student's tries three days ago, written and not, right, wrong, made right
# by the teacher, contested, sent twice, with a comment, on a superseded revision, and in the entry test. Every text is invented.
#
#   text-sentence  4 tries  a «play» made right by the teacher (@resolved_try), the same sent to «Fai controllare» (@contested_try), «don't eat» right
#                           (@right_try) and a whole sentence round the key's words (@sentence_try)   → flagged: manual_correction
#   text-word      5 tries  «neighbourhod» (@near_try), «kitchen» twice (@first_send, @resend), «xyz» with a comment on its serve (@commented_try),
#                           «banana» (@plain_try)                                                      → flagged: many_not_right
#   demo-item-2    6 tries  three right, three wrong (a number item)                                  → exactly half: not flagged
#   demo-item-1    1 try    on a revision that a newer one replaced                                    → left out, counted as superseded
#   diag-text-1    3 answers in the entry test: «1 mela» made right by the teacher (@diag_resolved), «no» (@diag_plain), «non lo so»  → flagged: manual_correction
module GradingReviewWorld
  include PracticeTextWorld

  def build_grading_review_world
    build_text_world
    @base = (Time.current.utc - 3.days).beginning_of_day + 8.hours # 08:00 UTC, three days ago: every try is in the past, on the same day
    @clock = Diagnosis::FakeClock.new(@base)
    @text_t = @base + 2.hours
    make_recorded_tries
    make_written_tries
    make_number_tries
    make_superseded_try
    make_diagnosis_answers
  end

  def instance_n(revision, n) = revision.instances.order(:id).offset(n).first

  def text_serve(revision, n, at: @clock.now) = make_serve(@official, @text_topic, instance_n(revision, n), skill_key: SKILL, at: at)

  # What the recorder did: «play» wrong (then made right by the teacher), the same contested, «don't eat» right.
  def make_recorded_tries
    resolved = text_serve(@sentence, 0)
    answer!(resolved, "play", student: @official)
    @resolved_try = resolved.attempts.sole
    @resolution = Decision.create!(kind: "resolve_attempt", subject: @subject, student: @official, request_id: SecureRandom.hex(4), teacher_login: "nik", remote_addr: "127.0.0.1",
                                   payload_json: JSON.generate(attempt_id: @resolved_try.id, attempt_kind: "practice", practice_serve_id: resolved.id, try_number: 1,
                                                               verdict: "correct", reason_it: "Era giusta."))
    @contested_serve = text_serve(@sentence, 1)
    answer!(@contested_serve, "play", student: @official)
    @contested_try = @contested_serve.attempts.sole
    Practice::Contest.new(student: @official, course_view: Course::StudentView.new(@official), clock: @clock).call(serve_id: @contested_serve.id)
    right = text_serve(@sentence, 2)
    answer!(right, "don't eat", student: @official)
    @right_try = right.attempts.sole
  end

  # Rows written as they stood in the ledger, at times of their own: a whole sentence, a typo, the same answer twice, a comment, a plain wrong one.
  def make_written_tries
    @sentence_try = make_try(text_serve(@sentence, 3, at: @text_t), raw: "My parents don't really eat meat", verdict: "wrong", at: @text_t + 60)
    @near_try = make_try(text_serve(@word, 0, at: @text_t + 120), raw: "neighbourhod", verdict: "wrong", at: @text_t + 180)
    send_serve = text_serve(@word, 1, at: @text_t + 240)
    @first_send = make_try(send_serve, try_number: 1, raw: "kitchen", verdict: "wrong", at: @text_t + 300)
    @resend = make_try(send_serve, try_number: 2, raw: "Kitchen ", verdict: "wrong", at: @text_t + 360)
    @commented_serve = text_serve(@word, 2, at: @text_t + 420)
    @commented_try = make_try(@commented_serve, raw: "xyz", verdict: "wrong", at: @text_t + 480)
    @comment = make_comment(practice_serve: @commented_serve, page_kind: "practice", page_path: "/topics/#{TOPIC}/practice/#{SKILL}", created_at: @text_t + 540)
    @plain_try = make_try(text_serve(@word, 3, at: @text_t + 600), raw: "banana", verdict: "wrong", at: @text_t + 660)
  end

  def make_comment(over = {})
    Comment.create!({ student: @official, client_comment_id: "c-#{SecureRandom.hex(6)}", reason: "error", text_it: "Non torna.", page_path: "/today", page_kind: "today",
                      subject: @subject, viewport_width: 390, viewport_height: 800, theme: "cream", text_size: "normal" }.merge(over))
  end

  # Six tries of demo-item-2, three right and three wrong, each its own serve.
  def make_number_tries
    @number_tries = %w[correct wrong correct wrong correct wrong].each_with_index.map do |verdict, i|
      at = @text_t + 3600 + i * 120
      make_try(make_serve(@official, @topic_revision, instance_n(@revisions[1], i), skill_key: SKILL, at: at), raw: "9", verdict: verdict, at: at + 60)
    end
  end

  # A wrong try on demo-item-1, and then a second revision of the item: the try is on a revision that is no longer the current one.
  def make_superseded_try
    at = @text_t + 7200
    @superseded_try = make_try(make_serve(@official, @topic_revision, instance_n(@revisions[0], 0), skill_key: SKILL, at: at), raw: "9", verdict: "wrong", at: at + 60)
    ItemRevision.create!(item: @revisions[0].item, seq: 2, body_json: @revisions[0].body_json, file_sessions_json: "{}")
  end

  # The entry test: «1 mela» (key «1») graded wrong and made right by the teacher, «no» wrong, and a «non lo so».
  def make_diagnosis_answers
    @diag_revision = make_revision("diag-text-1", SKILL, component: "normalized_text", instances: 3)
    instances = @diag_revision.instances.order(:id).to_a
    blueprint = BlueprintRevision.create!(subject: @subject, skill_graph_revision: @graph, seq: 1, body_json: JSON.generate(subject: "math", entries: [ { skill: SKILL, items: [] } ]))
    run = DiagnosisRun.create!(student: @official, subject: @subject, blueprint_revision: blueprint, sequence: 1, seed_salt: "s", rules_version: "v1", engine_version: "e1")
    start = @base - 1.day
    DiagnosisEvent.create!(diagnosis_run: run, seq: 1, kind: "sitting_started", payload_json: "{}", at: start)
    answers = [ [ "1 mela", "wrong" ], [ "no", "wrong" ], [ Grading::DONT_KNOW_RAW, "dont_know" ] ]
    @diag_tries = answers.each_with_index.map do |(raw, verdict), i|
      event = DiagnosisEvent.create!(diagnosis_run: run, seq: i + 2, kind: "item_served", payload_json: JSON.generate(reason: "next"), at: start + (i + 1) * 120)
      ItemServed.create!(diagnosis_event: event, item_instance: instances[i], skill_key: SKILL, shown_order_json: "{}", id_map_json: "{}")
      attempt = Attempt.create!(student: @official, context: "diagnosis", served_event: event, client_attempt_id: "d-#{SecureRandom.hex(6)}", item_instance: instances[i],
                                raw: raw, source: "text", answered_at: start + (i + 1) * 120 + 60)
      AttemptGrading.create!(attempt: attempt, seq: 1, verdict: verdict, error_codes_json: "[]", method: "exact", grader: "closed", grader_version: "test", source: "sync")
      attempt
    end
    @diag_resolved, @diag_plain, @diag_dont_know = @diag_tries
    @diag_resolution = Decision.create!(kind: "resolve_attempt", subject: @subject, student: @official, request_id: SecureRandom.hex(4), teacher_login: "nik", remote_addr: "127.0.0.1",
                                        payload_json: JSON.generate(attempt_id: @diag_resolved.id, verdict: "correct", reason_it: "Va bene anche così."))
  end

  # The row of the review's list for a ref such as practice-12.
  def review_try(review, record, kind: "practice") = review.tries.find { |t| t[:ref] == "#{kind}-#{record.id}" }
end
