Rails.application.routes.draw do
  # A topic key is its lesson's key (A1): kind, subject, slug.
  topic_key = /(ripasso|ponte|lezione|extra)\.[a-z_]+\.[a-z0-9]+(-[a-z0-9]+)*/
  web = Banco::ListenerConstraint.new(:web)
  api = Banco::ListenerConstraint.new(:api)
  # D-332: the teacher's pages that only read (GET) answer on the web listener and on the view listener (view links);
  # every POST and every student or preview route stays web-only.
  web_or_view = Banco::ListenerConstraint.new(:web, :view)
  view_only = Banco::ListenerConstraint.new(:view)

  # The teacher's reading pages, for the teacher and the guest on web and for a view link on view (D-332). The same
  # paths and route names as before the view listener existed; their POSTs are in the web block below.
  constraints(web_or_view) do
    get "teacher" => "teacher#show"
    get "teacher/items/:revision_id" => "teacher/items#show", constraints: { revision_id: /\d+/ }, format: false
    scope "teacher", module: "teacher", format: false do
      key = { key: /[a-z_]+/ }
      get "subjects/:key/graph" => "graphs#show", constraints: key, as: :teacher_graph
      get "subjects/:key/test" => "tests#show", constraints: key, as: :teacher_test
      get "subjects/:key/test/all" => "tests#all", constraints: key, as: :teacher_test_all
      get "subjects/:key/test/skills/:skill" => "tests#skill", constraints: key.merge(skill: /[a-z0-9][a-z0-9._\-]*/), as: :teacher_test_skill
      get "subjects/:key/report" => "reports#show", constraints: key, as: :teacher_report
      get "subjects/:key/course" => "courses#show", constraints: key, as: :teacher_course
      get "subjects/:key/topics/:topic" => "topics#show", constraints: key.merge(topic: topic_key), as: :teacher_topic
      get "subjects/:key/practice" => "practice#show", constraints: key, as: :teacher_practice
      get "subjects/:key/practice/skills/:skill" => "practice#skill", constraints: key.merge(skill: /[a-z0-9][a-z0-9._\-]*/), as: :teacher_practice_skill
      get "corrections" => "corrections#show", as: :teacher_corrections
      # Who did what (D-334): the teachers' and bots' actions, read-only.
      get "activity" => "activity#show", as: :teacher_activity
      # The student's comments (D-304): the teacher reads and answers; a guest sees the counts only.
      get "comments" => "comments#show", as: :teacher_comments
      get "search" => "search#show", as: :teacher_search
      get "findings" => "findings#show", as: :teacher_findings
      get "students" => "students#show", as: :teacher_students
      get "dashboard/state" => "dashboard#state", as: :teacher_dashboard_state
      get "dashboard/fragment" => "dashboard#fragment", as: :teacher_dashboard_fragment
      get "refs/:key" => "refs#show", constraints: { key: /[a-z0-9][a-z0-9._-]*/ }, as: :teacher_ref
      # Free pages (D-290): the screenshots of a page validation and the browser matrix page.
      get "page-revisions/:page_revision_id/shots" => "page_shots#index", constraints: { page_revision_id: /\d+/ }, as: :teacher_page_shots
      get "page-revisions/:page_revision_id/shots/:sha256" => "page_shots#show", constraints: { page_revision_id: /\d+/, sha256: /[0-9a-f]{64}/ }, as: :teacher_page_shot
      get "pages/selftest" => "pages#selftest", as: :teacher_pages_selftest
      get "lesson-revisions/:lesson_revision_id/shots" => "lesson_shots#index", constraints: { lesson_revision_id: /\d+/ }, as: :teacher_lesson_shots
      get "lesson-revisions/:lesson_revision_id/shots/:sha256" => "lesson_shots#show", constraints: { lesson_revision_id: /\d+/, sha256: /[0-9a-f]{64}/ }, as: :teacher_lesson_shot
      get "items/:revision_id/play" => "item_plays#show", constraints: { revision_id: /\d+/ }, as: :teacher_item_play
      get "items/:revision_id/play/data" => "item_plays#data", constraints: { revision_id: /\d+/ }, as: :teacher_item_play_data
      # The box of a lesson/2 (R3, A14): the full body. Nothing is recorded.
      get "lesson-revisions/:id/full.json" => "lesson_revisions#full", constraints: { id: /\d+/ }, format: false
    end
    # The poster of a free page (D-290): the validation screenshot by content address, for every signed-in role.
    get "page-posters/:sha" => "page_posters#show", constraints: { sha: /[0-9a-f]{64}/ }, format: false
    # Figures drawn by agents: images only, named by their digest.
    get "assets/items/:sha256.svg" => "item_assets#show", constraints: { sha256: /[0-9a-f]{64}/ }, format: false
  end

  # View listener (D-332): a view link's redemption, the only page that needs no session, and a plain refusal of every
  # method but GET and HEAD (a POST would otherwise fall to the 404 of the unmatched paths; it is a 403 here). A callable
  # `constraints:` on a route replaces the block's constraint, so the refusal checks the listener itself.
  view_write = ->(request) { view_only.matches?(request) && !(request.get? || request.head?) }
  constraints(view_only) do
    get "v" => "view_links#redeem", format: false
  end
  match "*path", to: "view_links#refuse", via: :all, format: false, constraints: view_write

  # Web listener: the student and the teacher, behind Traefik and Authelia.
  constraints(web) do
    get "up" => "rails/health#show", as: :rails_health_check
    # The front door (D-240): a student goes to Oggi, the teacher and a guest to /teacher, anyone else gets the 404.
    get "/" => "home#show", format: false

    # One test, played by the student (/diagnosis) or by the teacher as the
    # student (/teacher/preview, route default preview: true, never a parameter).
    concern :sitting do
      post "subjects/:key" => "sittings#create", as: :subject_start, constraints: { key: /[a-z_]+/ }
      get "runs/:run_id" => "sittings#show", as: :run
      post "runs/:run_id/step" => "sittings#step", as: :run_step
      post "runs/:run_id/events" => "sittings#events", as: :run_events
      get "runs/:run_id/results" => "sittings#results", as: :run_results
      post "runs/:run_id/flags" => "sittings#flag", as: :run_flags
      post "runs/:run_id/support" => "sittings#support", as: :run_support
      post "answers" => "answers#create", as: :answers
    end

    get "diagnosis" => "diagnosis#show"
    scope "diagnosis" do
      post "preferences" => "preferences#update", as: :preferences
      get "warmup" => "warmup#show", as: :warmup
      get "warmup/tasks" => "warmup#tasks", as: :warmup_tasks
      post "warmup/answers" => "warmup#answer", as: :warmup_answers
      post "warmup/complete" => "warmup#complete", as: :warmup_complete
      concerns :sitting
    end
    # The course of Phase 1b (A9): Oggi, the subjects, a topic, its lesson and its practice. Students only, official
    # and trial; the teacher and guests get 403. The official student sees nothing until release_course. The same
    # pages are the teacher's preview under /teacher/preview (D-309), where the route default says who is acting.
    concern :course_pages do
      topic = { topic: /(ripasso|ponte|lezione|extra)\.[a-z_]+\.[a-z0-9]+(-[a-z0-9]+)*/ }
      get "today" => "course#today"
      get "subjects" => "course#subjects"
      get "subjects/:key" => "course#subject", constraints: { key: /[a-z_]+/ }
      get "civics" => "course#civics"
      get "topics/:topic" => "topics#show", constraints: topic
      get "topics/:topic/lesson" => "lessons#show", constraints: topic
      post "topics/:topic/lesson/exercises/:n/solution" => "lessons#solution", constraints: topic.merge(n: /\d+/)
      # Lesson/2 (R3, A9, A11): the checks (a block, a blank of an example, an exercise's check) and the events batch.
      n = /\d+/
      post "topics/:topic/lesson/checks/:card/:block" => "lesson_checks#create", constraints: topic.merge(card: n, block: n)
      post "topics/:topic/lesson/checks/:card/:block/:step" => "lesson_checks#create", constraints: topic.merge(card: n, block: n, step: n)
      post "topics/:topic/lesson/checks/:card/:block/ex/:n" => "lesson_checks#create", constraints: topic.merge(card: n, block: n, n: n)
      post "topics/:topic/lesson/checks/:card/:block/ex/:n/:part" => "lesson_checks#create", constraints: topic.merge(card: n, block: n, n: n, part: n)
      post "topics/:topic/lesson/events" => "lesson_events#create", constraints: topic
      get "topics/:topic/practice/:skill" => "practice#show", constraints: topic.merge(skill: /[a-z_]+\.[a-z0-9]+(-[a-z0-9]+)*/)
      post "practice/serves" => "practice#serve"
      post "practice/answers" => "practice#answer"
      post "practice/serves/:serve_id/hint" => "practice#hint", constraints: { serve_id: /\d+/ }
      post "practice/serves/:serve_id/solution" => "practice#solution", constraints: { serve_id: /\d+/ }
      post "practice/serves/:serve_id/contest" => "practice#contest", constraints: { serve_id: /\d+/ }
      post "practice/serves/:serve_id/draft" => "practice#draft", constraints: { serve_id: /\d+/ }
      get "practice/exercises" => "practice#exercises"
      get "settings" => "settings#show"
      get "search" => "search#show"
    end
    scope format: false do
      concerns :course_pages
      post "questions" => "questions#create"
      # Comments anywhere (D-304): the student writes a comment on any page and reads the answers. Students only.
      get "comments" => "comments#index"
      post "comments" => "comments#create"
      post "comments/:id/reply" => "comments#reply", constraints: { id: /\d+/ }, as: :comment_reply
    end

    # The teacher's decisions (D-08): the only writes of DecisionRecorder. POST only,
    # ids in the path, everything else in the body.
    scope "teacher", controller: "teacher/decisions", format: false do
      id = /\d+/
      post "skill-graph-revisions/:revision_id/approve", action: :approve_skill_graph, constraints: { revision_id: id }
      post "blueprint-revisions/:revision_id/approve", action: :approve_blueprint, constraints: { revision_id: id }
      post "blueprint-revisions/:revision_id/confirm-reviewed", action: :confirm_test_reviewed, constraints: { revision_id: id }
      post "findings/:finding_id/disposition", action: :dispose_finding, constraints: { finding_id: id }
      post "grade-proposals/:grade_proposal_id/confirm", action: :confirm_grade, constraints: { grade_proposal_id: id }
      post "grade-proposals/:grade_proposal_id/reject", action: :reject_grade, constraints: { grade_proposal_id: id }
      post "attempts/:attempt_id/resolve", action: :resolve_attempt, constraints: { attempt_id: id }
      post "runs/:run_id/void", action: :void_run, constraints: { run_id: id }
      post "runs/:run_id/extend", action: :extend_run, constraints: { run_id: id }
      post "runs/:run_id/close", action: :close_run, constraints: { run_id: id }
      post "item-revisions/:item_revision_id/send-back", action: :send_back_item, constraints: { item_revision_id: id }
      post "item-revisions/:item_revision_id/void-attempts", action: :void_revision_attempts, constraints: { item_revision_id: id }
      post "subjects/:subject/follow-opinions", action: :follow_opinions, constraints: { subject: /[a-z_]+/ }
      post "subjects/:subject/formula-sheet", action: :set_formula_sheet, constraints: { subject: /[a-z_]+/ }
      post "subjects/:subject/kind-override", action: :kind_override, constraints: { subject: /[a-z_]+/ }
      post "topic-revisions/:revision_id/approve", action: :approve_topic, constraints: { revision_id: id }
      post "lesson-revisions/:lesson_revision_id/send-back", action: :send_back_lesson, constraints: { lesson_revision_id: id }
      post "subjects/:subject/course-release", action: :release_course, constraints: { subject: /[a-z_]+/ }
      post "release", action: :release
      post "consent", action: :consent
    end

    # The heartbeat of the teacher's minutes and the POSTs of the lesson box and the comments; the teacher's GET pages are
    # in the web_or_view block at the top (D-332).
    scope "teacher", module: "teacher", format: false do
      %w[reply read resolve reopen].each do |action|
        post "comments/:comment_id/#{action}" => "comments##{action}", constraints: { comment_id: /\d+/ }, as: :"teacher_comment_#{action}"
      end
      post "activity" => "activity#create"
      # The box of a lesson/2 (R3, A14): a check graded with the seed "preview", a solution. Nothing is recorded.
      lr = { id: /\d+/ }
      n = /\d+/
      post "lesson-revisions/:id/checks/:card/:block" => "lesson_revisions#check", constraints: lr.merge(card: n, block: n)
      post "lesson-revisions/:id/checks/:card/:block/:step" => "lesson_revisions#check", constraints: lr.merge(card: n, block: n, step: n)
      post "lesson-revisions/:id/checks/:card/:block/ex/:n" => "lesson_revisions#check", constraints: lr.merge(card: n, block: n, n: n)
      post "lesson-revisions/:id/checks/:card/:block/ex/:n/:part" => "lesson_revisions#check", constraints: lr.merge(card: n, block: n, n: n, part: n)
      post "lesson-revisions/:id/exercises/:n/solution" => "lesson_revisions#solution", constraints: lr.merge(n: n)
      post "topic-revisions/:revision_id/seen" => "seen#create", constraints: { revision_id: /\d+/ }, as: :teacher_topic_seen
    end

    scope "teacher/preview", as: :preview, defaults: { preview: true } do
      # The teacher walks the student's site (D-309): Oggi at the root, the entry test list at /test, the same pages as S.
      get "/" => "course#today", as: :index
      get "test" => "teacher/previews#index", as: :test
      post "view" => "teacher/previews#view", as: :view
      post "reset" => "teacher/previews#reset", as: :reset
      scope format: false do
        concerns :course_pages
      end
      post "preferences" => "preferences#update", as: :preferences
      get "warmup" => "warmup#show", as: :warmup
      get "warmup/tasks" => "warmup#tasks", as: :warmup_tasks
      post "warmup/answers" => "warmup#answer", as: :warmup_answers
      post "warmup/complete" => "warmup#complete", as: :warmup_complete
      post "runs/:run_id/close" => "sittings#close", as: :run_close
      concerns :sitting
    end
  end

  # API listener: agent token only.
  constraints(api) do
    get "api/v1/schema" => "api/v1/schema#show"
    post "api/v1/diagnosis/simulate" => "api/v1/diagnosis#simulate", format: false
    get "api/v1/briefs/:name" => "api/v1/briefs#show", constraints: { name: /[a-z][a-z0-9-]*/ }, format: false
    get "api/v1/diagnosis/report" => "api/v1/reports#show", format: false
    get "api/v1/health" => "api/v1/health#show", format: false
    get "api/v1/status" => "api/v1/status#show", format: false
    get "api/v1/items" => "api/v1/items#index", format: false
    get "api/v1/search" => "api/v1/search#show", format: false
    get "api/v1/references" => "api/v1/references#index", format: false
    get "api/v1/references/:key" => "api/v1/references#show", constraints: { key: /[a-z0-9][a-z0-9-]*/ }, format: false
    get "api/v1/syllabus/:source/lines" => "api/v1/syllabus#lines", constraints: { source: /[a-z0-9][a-z0-9-]*/ }, format: false

    # The content agent's cycle on an item (A-04, A-06, E-05).
    get "api/v1/work/items/:item" => "api/v1/work#open", constraints: { item: /[a-z0-9][a-z0-9_-]*/ }, format: false
    post "api/v1/work/submit" => "api/v1/work#submit", format: false
    get "api/v1/work/revisions/:revision" => "api/v1/work#status", constraints: { revision: /\d+/ }, format: false

    # Independence and the evening loop (A-04, A-05, B-06): sessions, the expert review and
    # the blind solve of a revision, grade proposals. No route decides anything.
    post "api/v1/sessions" => "api/v1/sessions#create", format: false
    revision = { revision: /\d+/ }
    get "api/v1/revisions/:revision/review" => "api/v1/reviews#open", constraints: revision, format: false
    post "api/v1/revisions/:revision/review" => "api/v1/reviews#submit", constraints: revision, format: false
    get "api/v1/revisions/:revision/solve" => "api/v1/solves#open", constraints: revision, format: false
    post "api/v1/revisions/:revision/solve" => "api/v1/solves#submit", constraints: revision, format: false
    # The shots of an item revision at 390 px (D-336): requested on demand by a content role, read by every role.
    get "api/v1/item-revisions/:revision/shots" => "api/v1/item_shots#index", constraints: revision, format: false
    post "api/v1/item-revisions/:revision/shots" => "api/v1/item_shots#create", constraints: revision, format: false
    get "api/v1/item-revisions/:revision/shots/:sha" => "api/v1/item_shots#show", constraints: revision.merge(sha: /[0-9a-f]{64}/), format: false
    get "api/v1/submissions/pending" => "api/v1/grades#pending", format: false
    post "api/v1/attempts/:attempt/grade-proposals" => "api/v1/grades#propose", constraints: { attempt: /\d+/ }, format: false

    # The author answers the findings (D-220), an item's (a number) or a lesson review's (L<review>-<n>, D-313);
    # the teacher alone decides about them.
    post "api/v1/findings/:finding/responses" => "api/v1/findings#respond", constraints: { finding: /\d+|L\d+-\d+/ }, format: false
    # The third reviewer reads a finding and says who is right (D-222); this too decides nothing.
    post "api/v1/findings/:finding/assessments" => "api/v1/findings#assess", constraints: { finding: /\d+|L\d+-\d+/ }, format: false

    # The graph and the entry test of a subject.
    subject = { subject: /[a-z_]+/ }
    get "api/v1/subjects/:subject/findings" => "api/v1/findings#index", constraints: subject, format: false
    get "api/v1/subjects/:subject/skill-graph" => "api/v1/skill_graphs#open", constraints: subject, format: false
    post "api/v1/subjects/:subject/skill-graph" => "api/v1/skill_graphs#submit", constraints: subject, format: false
    get "api/v1/subjects/:subject/skill-graph/coverage" => "api/v1/skill_graphs#coverage", constraints: subject, format: false
    get "api/v1/subjects/:subject/blueprint" => "api/v1/blueprints#open", constraints: subject, format: false
    post "api/v1/subjects/:subject/blueprint" => "api/v1/blueprints#submit", constraints: subject, format: false

    # The course of Phase 1b (D-223..D-232): the map, the lessons, their reviews, the topics. No route decides.
    get "api/v1/subjects/:subject/course" => "api/v1/courses#open", constraints: subject, format: false
    post "api/v1/subjects/:subject/course" => "api/v1/courses#submit", constraints: subject, format: false
    get "api/v1/subjects/:subject/lessons" => "api/v1/lessons#index", constraints: subject, format: false
    get "api/v1/subjects/:subject/topics" => "api/v1/topics#index", constraints: subject, format: false
    get "api/v1/subjects/:subject/practice/progress" => "api/v1/practice_progress#show", constraints: subject, format: false
    lesson = { lesson: /(ripasso|ponte|lezione|extra)\.[a-z_]+\.[a-z0-9-]+/ }
    post "api/v1/lessons/submit" => "api/v1/lessons#submit", format: false
    get "api/v1/lessons/:lesson" => "api/v1/lessons#open", constraints: lesson, format: false
    get "api/v1/lesson-revisions/:revision" => "api/v1/lessons#status", constraints: revision, format: false
    get "api/v1/lesson-revisions/:revision/shots" => "api/v1/lesson_shots#index", constraints: revision, format: false
    get "api/v1/lesson-revisions/:revision/shots/:sha" => "api/v1/lesson_shots#show", constraints: revision.merge(sha: /[0-9a-f]{64}/), format: false
    get "api/v1/lesson-revisions/:revision/review" => "api/v1/lesson_reviews#open", constraints: revision, format: false
    post "api/v1/lesson-revisions/:revision/review" => "api/v1/lesson_reviews#submit", constraints: revision, format: false
    # Free pages, release 2 (D-290, SPEC B9). No route decides.
    page = { key: /[a-z_]+\.[a-z0-9]+(?:-[a-z0-9]+)*/ }
    get "api/v1/subjects/:subject/pages" => "api/v1/pages#index", constraints: subject, format: false
    post "api/v1/pages/submit" => "api/v1/pages#submit", format: false
    get "api/v1/pages/:key" => "api/v1/pages#open", constraints: page, format: false
    get "api/v1/page-revisions/:revision" => "api/v1/pages#status", constraints: revision, format: false
    get "api/v1/page-revisions/:revision/shots" => "api/v1/pages#shots", constraints: revision, format: false
    get "api/v1/page-revisions/:revision/shots/:sha" => "api/v1/pages#shot", constraints: revision.merge(sha: /[0-9a-f]{64}/), format: false
    get "api/v1/page-revisions/:revision/diff" => "api/v1/pages#diff", constraints: revision, format: false
    get "api/v1/page-revisions/:revision/review" => "api/v1/page_reviews#open", constraints: revision, format: false
    post "api/v1/page-revisions/:revision/review" => "api/v1/page_reviews#submit", constraints: revision, format: false
    get "api/v1/topics/:topic" => "api/v1/topics#open", constraints: { topic: lesson[:lesson] }, format: false
    post "api/v1/topics/:topic" => "api/v1/topics#submit", constraints: { topic: lesson[:lesson] }, format: false

    # The teacher's pages and the student's progress as JSON (D-328): read-only, every token role. Built on the read models of the
    # pages (Teacher::ApiView, Course::StudentProgress); they record no "read" event.
    view_subject = { key: /[a-z_]+/ }
    get "api/v1/teacher/home" => "api/v1/teacher_views#home", format: false
    get "api/v1/teacher/subjects/:key/course" => "api/v1/teacher_views#course", constraints: view_subject, format: false
    get "api/v1/teacher/subjects/:key/topics/:topic" => "api/v1/teacher_views#topic", constraints: view_subject.merge(topic: topic_key), format: false
    get "api/v1/teacher/subjects/:key/test" => "api/v1/teacher_views#test", constraints: view_subject, format: false
    get "api/v1/students/:key/progress" => "api/v1/progress#show", constraints: { key: /[a-z0-9-]+/ }, format: false
    # What the student does next, per subject (D-333), and the whole picture in one read: the pages' own read models again, nothing written.
    get "api/v1/students/:key/next" => "api/v1/progress#upcoming", constraints: { key: /[a-z0-9-]+/ }, format: false
    get "api/v1/digest" => "api/v1/digest#show", format: false

    # The public API (D-327): the teacher's decisions and the student's comments and pending answers, for the tokens of
    # the roles bot_read (reads) and teacher (reads, decisions, comment actions). Every write is a dry run unless the
    # body says confirm: true.
    get "api/v1/decisions" => "api/v1/decisions#index", format: false
    post "api/v1/decisions" => "api/v1/decisions#create", format: false
    get "api/v1/comments" => "api/v1/comments#index", format: false
    comment = { id: /\d+/ }
    get "api/v1/comments/:id" => "api/v1/comments#show", constraints: comment, format: false
    %w[reply resolve reopen read].each do |action|
      post "api/v1/comments/:id/#{action}" => "api/v1/comments##{action}", constraints: comment, format: false
    end
    get "api/v1/answers/pending" => "api/v1/answers#pending", format: false
    # Who did what (D-334): the feed of the teachers' and bots' actions, for bot_read and teacher tokens.
    get "api/v1/activity" => "api/v1/activity#show", format: false

    # Staying current (D-330): the token itself (never its secret; any token role), what changed in the software, the two docs
    # the bot lives by and the CLI's release build of this image. Doc and binary names come from allowlists. The last four
    # (updates, one decision's text, docs, cli) need no token at all (D-333): the public repo's content, no student data.
    get "api/v1/token" => "api/v1/tokens#show", format: false
    get "api/v1/updates" => "api/v1/updates#show", format: false
    get "api/v1/updates/decisions/:number" => "api/v1/updates#entry", constraints: { number: /[A-Za-z0-9-]+/ }, format: false
    get "api/v1/docs/:name" => "api/v1/updates#doc", constraints: { name: /[a-z]+/ }, format: false
    get "api/v1/cli/:file" => "api/v1/updates#cli", constraints: { file: /banco-[a-z0-9]+-[a-z0-9]+(?:\.exe)?/ }, format: false

    # View links (D-332): a bot_read or teacher token creates, lists and revokes the temporary URLs that open the teacher's pages
    # read-only on the view listener. The one POST a bot_read token may send (Api::BaseController.reader_grants).
    post "api/v1/view-links" => "api/v1/view_links#create", format: false
    get "api/v1/view-links" => "api/v1/view_links#index", format: false
    post "api/v1/view-links/:id/revoke" => "api/v1/view_links#revoke", constraints: { id: /\d+/ }, format: false
    post "api/v1/view-links/revoke-all" => "api/v1/view_links#revoke_all", format: false
  end

  # Harness listener: the page and the files Chrome loads to run an agent's
  # generator or verify (A-02). Internal; never published.
  harness = Banco::ListenerConstraint.new(:harness)
  constraints(harness) do
    get "h/:token/:file" => "harness#show", constraints: { token: /[A-Za-z0-9_.-]+/, file: /harness\.html|runner\.mjs|generator\.mjs|verify\.mjs/ }, format: false
    get "h/:token/lesson-render.html" => "harness#lesson", constraints: { token: /[A-Za-z0-9_.-]+/ }, format: false
    get "h/:token/item-render.html" => "harness#item", constraints: { token: /[A-Za-z0-9_.-]+/ }, format: false
    get "assets/items/:sha256.svg" => "harness#item_asset", constraints: { sha256: /[0-9a-f]{64}/ }, format: false
    get "h/:token/:file" => "harness#page_host", constraints: { token: /[A-Za-z0-9_.-]+/, file: /page-host\.html|page-host\.mjs/ }, format: false
    get "lib/:file" => "harness#lib", constraints: { file: /rng\.mjs|fmt\.mjs/ }, format: false
  end

  # Everything else, including any route on the wrong listener: 404.
  match "*path", to: "not_found#show", via: :all
  root "not_found#show"
end
