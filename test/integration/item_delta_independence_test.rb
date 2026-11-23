require "test_helper"
require_relative "../support/course_rows"

# D-391: the independence of a review and of a blind solve of an item revision is judged against the authors of the
# revisions after the last approved base, when that base has both an independent review and an independent blind solve on
# record; otherwise against every author of the item. The write-time refusal (Providers.refusal with the revision) and the
# read-time counting (Providers.counting, ItemRevision#counting_reviews and #counting_blind_solves) are one rule
# (ItemSessions#model_authors), so they agree, and Review::Gate sees the delta. D-374's rule, for items.
class ItemDeltaIndependenceTest < ActionDispatch::IntegrationTest
  include CourseRows

  OPUS = "claude-opus-5-5".freeze
  SONNET = "claude-sonnet-5-5".freeze
  KEY = "delta-item-1".freeze
  SKILL = "math.integer-operations".freeze

  setup do
    @token = ApiToken.issue!(role: "agent_claude", label: "item delta test")
    build_course
    @item = Item.create!(subject: @subject, key: KEY, kind: "practice_item")
    @opus_author = session!(:author, OPUS)
    @sonnet_author = session!(:author, SONNET)
  end

  def session!(role, model) = AgentSession.create!(label: "t", role: role.to_s, agent: "test", model: model)

  # An item revision the way `work submit` stores it: file_sessions carries the writer of every file as it stands, the
  # session of an unchanged file included. +generator+ is the text of generator.mjs (none when nil).
  def revision!(author, generator: nil, note: nil)
    previous = ItemRevision.where(item_id: @item.id).order(:seq).last
    seq = (previous&.seq || 0) + 1
    body = JSON.generate(schema: "banco.item/1", schema_version: 1, kind: "practice_item", subject: "math", skill: SKILL, component: "number", level: 1,
                         expected_seconds: 60, note: note || "revision #{seq} by #{author.id}")
    files = { "item.json" => body }
    files["generator.mjs"] = generator if generator
    sessions = files.to_h do |name, text|
      same = previous && previous.files[name] == text
      [ name, same ? previous.file_sessions[name] : author.id ]
    end
    revision = ItemRevision.create!(item: @item, seq: seq, base_revision_id: previous&.id, body_json: body, files_json: generator && JSON.generate("generator.mjs" => generator),
                                    file_sessions_json: JSON.generate(sessions), author_session: author)
    ItemValidation.create!(item_revision: revision, seq: 1, status: "passed", codes_json: "[]")
    2.times do |i|
      ItemInstance.create!(item_revision: revision, seed: i + 1, display_json: JSON.generate(stem_it: "#{KEY} #{seq} #{i}"), answer_json: JSON.generate("1"),
                           fingerprint: Digest::SHA256.hexdigest("#{KEY}-#{seq}-#{i}"))
    end
    revision
  end

  def reviewed!(revision, by) = ItemReview.create!(item_revision: revision, agent_session: by, checklist_json: "[]")

  def solved!(revision, by) = BlindSolve.create!(item_revision: revision, agent_session: by, answers_json: "[]", results_json: "[]")

  # A review and a blind solve by two sessions on +model+ (reviewer, solver).
  def worked!(revision, model)
    [ reviewed!(revision, session!(:reviewer, model)), solved!(revision, session!(:solver, model)) ]
  end

  # The teacher approves a topic that pins the revision (what DecisionRecorder#approve_topic writes of it).
  def approve!(revision)
    Decision.create!(kind: "approve_topic", subject: @subject, request_id: SecureRandom.hex(4), teacher_login: "teacher", remote_addr: "127.0.0.1",
                     payload_json: JSON.generate(topic_revision_id: 1, topic: "ripasso.math.delta", seq: 1, item_revision_ids: [ revision.id ]))
  end

  def approve_by_blueprint!(revision)
    blueprint = BlueprintRevision.create!(subject: @subject, skill_graph_revision: @graph, seq: (BlueprintRevision.where(subject: @subject).maximum(:seq) || 0) + 1,
                                          body_json: JSON.generate(subject: "math", entries: [ { skill: SKILL, items: [ revision.id ] } ], descent: []))
    approve_blueprint!(@subject, blueprint)
  end

  def refusal(session, revision) = Providers.refusal(session, item: @item, revision: revision)

  def counts?(row) = Providers.counting([ row ], @item).any?

  def api(path, session, method: :get, body: nil)
    on(:api, path, method: method, headers: { "Authorization" => "Bearer #{@token}", "X-Banco-Session" => session.id.to_s }, params: body, as: body ? :json : nil)
  end

  # A Sonnet writes the item, an Opus reviews and solves it, the teacher approves, an Opus writes a fix.
  def sonnet_base_then_opus_fix
    @base = revision!(@sonnet_author)
    @base_review, @base_solve = worked!(@base, OPUS)
    approve!(@base)
    @fix = revision!(@opus_author)
  end

  test "after an independently reviewed and solved approved base, a Sonnet reviews and solves an Opus fix and it counts for the gate; an Opus is refused" do
    sonnet_base_then_opus_fix
    sonnet_reviewer = session!(:reviewer, SONNET)
    sonnet_solver = session!(:solver, SONNET)
    opus_reviewer = session!(:reviewer, OPUS)
    opus_solver = session!(:solver, OPUS)

    assert_nil refusal(sonnet_reviewer, @fix)
    assert_nil refusal(sonnet_solver, @fix)
    assert_match(/different model/, refusal(opus_reviewer, @fix))
    assert_match(/different model/, refusal(opus_solver, @fix))

    # An Opus review and solve of the fix never count; the gate says so.
    opus_review = reviewed!(@fix, opus_reviewer)
    opus_solve = solved!(@fix, opus_solver)
    assert_not counts?(opus_review)
    assert_not counts?(opus_solve)
    assert_not Review::Gate.approvable?(@fix.reload)
    assert_match(/no independent expert review/, Review::Gate.check(@fix).reasons.join(" "))
    assert_match(/no independent blind solve/, Review::Gate.check(@fix).reasons.join(" "))

    review = reviewed!(@fix, sonnet_reviewer)
    solve = solved!(@fix, sonnet_solver)
    assert counts?(review)
    assert counts?(solve)
    assert_equal [ review ], @fix.counting_reviews
    assert_equal [ solve ], @fix.counting_blind_solves
    assert Review::Gate.approvable?(@fix.reload), Review::Gate.check(@fix).reasons.inspect
    assert Review::Gate.worked?(@fix)
    assert review.independent?
    assert_not opus_review.independent?
  end

  test "the same over the API: a fresh Sonnet opens and may submit, a fresh Opus is E-PROVIDER-NOT-ALLOWED at open and submit, for the review and the solve" do
    sonnet_base_then_opus_fix
    %w[review solve].each do |step|
      role = step == "review" ? :reviewer : :solver
      api("/api/v1/revisions/#{@fix.id}/#{step}", session!(role, SONNET))
      assert_response :ok, response.body
      opus = session!(role, OPUS)
      api("/api/v1/revisions/#{@fix.id}/#{step}", opus)
      assert_response :unprocessable_entity
      assert_equal "E-PROVIDER-NOT-ALLOWED", response.parsed_body["code"]
      api("/api/v1/revisions/#{@fix.id}/#{step}", opus, method: :post, body: { step => {} })
      assert_equal "E-PROVIDER-NOT-ALLOWED", response.parsed_body["code"]
    end
  end

  test "who may review stays by session; the model of an author of the delta is refused" do
    sonnet_base_then_opus_fix
    # The fix is by an Opus; a session on Opus is refused whoever it is, a session of the old Sonnet author may not review at all.
    assert_match(/different model/, refusal(session!(:reviewer, OPUS), @fix))
    assert_includes ItemSessions.new(@item).conflicts(@sonnet_author.id, "reviewer"), "author"
  end

  test "the base is the newest approved revision before the one read; the delta runs from it up to the revision" do
    sonnet_base_then_opus_fix
    later = revision!(@sonnet_author)
    sessions = ItemSessions.new(@item)
    assert_equal @base, sessions.base_of(@fix)
    assert_equal @base, sessions.base_of(later), "the fix was not approved: still the first revision"
    assert_nil sessions.base_of(@base)
    # The delta of `later` since the base holds both models: the Opus of the fix and the Sonnet of this revision.
    assert_equal [ @opus_author, @sonnet_author ].sort_by(&:id), sessions.model_authors(later)
    assert_match(/different model/, refusal(session!(:reviewer, OPUS), later))
    assert_match(/different model/, refusal(session!(:reviewer, SONNET), later))
    assert_nil refusal(session!(:reviewer, "gpt-5.2"), later)
  end

  test "an approval of the fix itself moves the base: a newer Sonnet revision is judged against its own delta" do
    sonnet_base_then_opus_fix
    worked!(@fix, SONNET)
    approve!(@fix)
    later = revision!(@sonnet_author)
    assert_equal @fix, ItemSessions.new(@item).base_of(later)
    assert_equal [ @sonnet_author ], ItemSessions.new(@item).model_authors(later)
    assert_nil refusal(session!(:reviewer, OPUS), later)
    assert_match(/different model/, refusal(session!(:reviewer, SONNET), later))
  end

  test "an approved entry test that pins the revision is a base too" do
    @base = revision!(@sonnet_author)
    worked!(@base, OPUS)
    approve_by_blueprint!(@base)
    fix = revision!(@opus_author)
    assert_equal @base, ItemSessions.new(@item).base_of(fix)
    assert_nil refusal(session!(:reviewer, SONNET), fix)
    assert_nil refusal(session!(:solver, SONNET), fix)
    assert_match(/different model/, refusal(session!(:reviewer, OPUS), fix))
  end

  test "without an approved base every author of the item counts, as before" do
    base = revision!(@sonnet_author)
    worked!(base, OPUS)
    fix = revision!(@opus_author)
    sonnet = session!(:reviewer, SONNET)
    opus = session!(:reviewer, OPUS)
    assert_match(/different model/, refusal(sonnet, fix))
    assert_match(/different model/, refusal(opus, fix))
    assert_match(/different model/, refusal(session!(:solver, SONNET), fix))
    assert_not counts?(reviewed!(fix, sonnet))
    assert_not counts?(reviewed!(fix, opus))
    assert_empty fix.counting_reviews
    assert_nil ItemSessions.new(@item).base_of(fix)
    assert_equal [ @opus_author, @sonnet_author ].sort_by(&:id), ItemSessions.new(@item).model_authors(base)
    assert_nil refusal(session!(:reviewer, "gpt-5.2"), fix)
  end

  test "a base whose own review was not independent, or whose own solve was not, or that has none, is no base" do
    # Approved, never reviewed or solved.
    base = revision!(@sonnet_author)
    approve!(base)
    fix = revision!(@opus_author)
    assert_nil ItemSessions.new(@item).base_of(fix)
    assert_match(/different model/, refusal(session!(:reviewer, SONNET), fix))

    # Its review is on the author's model: not independent.
    reviewed!(base, session!(:reviewer, SONNET))
    solved!(base, session!(:solver, OPUS))
    assert_nil ItemSessions.new(@item).base_of(fix), "the review shares the author's model"
    assert_match(/different model/, refusal(session!(:reviewer, SONNET), fix))
    assert_match(/different model/, refusal(session!(:solver, SONNET), fix))
  end

  test "an independent review is not enough: the base needs an independent blind solve too, and the other way round" do
    base = revision!(@sonnet_author)
    reviewed!(base, session!(:reviewer, OPUS))
    solved!(base, session!(:solver, SONNET))
    approve!(base)
    fix = revision!(@opus_author)
    assert_nil ItemSessions.new(@item).base_of(fix), "independent review, solve on the author's model"
    assert_match(/different model/, refusal(session!(:reviewer, SONNET), fix))

    solved!(base, session!(:solver, OPUS))
    assert_equal base, ItemSessions.new(@item).base_of(fix), "one independent solve is enough, as for the gate"
    assert_nil refusal(session!(:reviewer, SONNET), fix)

    other = Item.create!(subject: @subject, key: "delta-item-2", kind: "practice_item")
    @item = other
    second = revision!(@sonnet_author)
    reviewed!(second, session!(:reviewer, SONNET))
    solved!(second, session!(:solver, OPUS))
    approve!(second)
    second_fix = revision!(@opus_author)
    assert_nil ItemSessions.new(@item).base_of(second_fix), "independent solve, review on the author's model"
  end

  test "the measure is recursive: an approved Opus fix read by Sonnets is a base for the next revision; an approved revision that was not independent of its own delta is none, with no fallback" do
    sonnet_base_then_opus_fix
    # The fix (Opus) is read and solved by Sonnets: independent of its own delta (the Opus alone), though not of every author of the item.
    worked!(@fix, SONNET)
    approve!(@fix)
    third = revision!(@sonnet_author)
    assert_equal @fix, ItemSessions.new(@item).base_of(third)

    # The third revision is approved on a review by a Sonnet, the model of its own delta: it is no base, and the older fix is not reached for.
    fourth = revision!(@opus_author)
    reviewed!(third, session!(:reviewer, SONNET))
    solved!(third, session!(:solver, OPUS))
    approve!(third)
    assert_nil ItemSessions.new(@item).base_of(fourth)
    assert_match(/different model/, refusal(session!(:reviewer, SONNET), fourth))
  end

  test "an Opus that rewrites item.json and leaves a Sonnet's generator.mjs as it was is the only author of the delta" do
    @base = revision!(@sonnet_author, generator: "export function generate() { return {}; }")
    worked!(@base, OPUS)
    approve!(@base)
    @fix = revision!(@opus_author, generator: "export function generate() { return {}; }", note: "fixed stem")
    assert_equal({ "item.json" => @opus_author.id, "generator.mjs" => @sonnet_author.id }, @fix.file_sessions, "the server carries the old writer of the unchanged file")
    assert_equal [ @opus_author ], ItemSessions.new(@item).model_authors(@fix)
    assert_nil refusal(session!(:reviewer, SONNET), @fix)
    assert_match(/different model/, refusal(session!(:reviewer, OPUS), @fix))

    # Changing the generator makes its writer an author of the delta.
    third = revision!(@sonnet_author, generator: "export function generate() { return { n: 1 }; }", note: "fixed stem")
    assert_includes ItemSessions.new(@item).model_authors(third), @sonnet_author
  end

  test "the refusal and the counting agree for every model on every revision, for reviews and solves" do
    sonnet_base_then_opus_fix
    later = revision!(@sonnet_author)
    [ @base, @fix, later ].each do |revision|
      [ OPUS, SONNET, "gpt-5.2", "kimi-k3" ].each do |model|
        reviewer = session!(:reviewer, model)
        solver = session!(:solver, model)
        assert_equal refusal(reviewer, revision).nil?, counts?(reviewed!(revision, reviewer)), "review by #{model} on revision #{revision.seq}"
        assert_equal refusal(solver, revision).nil?, counts?(solved!(revision, solver)), "solve by #{model} on revision #{revision.seq}"
      end
    end
  end

  test "a later approval does not change how an earlier row counts" do
    sonnet_base_then_opus_fix
    good = reviewed!(@fix, session!(:reviewer, SONNET))
    bad = reviewed!(@fix, session!(:reviewer, OPUS))
    approve!(@fix)
    assert counts?(good)
    assert_not counts?(bad)
  end

  test "without the revision the refusal keeps every author; an author session has no model rule" do
    sonnet_base_then_opus_fix
    assert_match(/different model/, Providers.refusal(session!(:reviewer, SONNET), item: @item), "without the revision the old rule")
    assert_nil Providers.refusal(session!(:author, OPUS), item: @item, revision: @fix)
  end
end
