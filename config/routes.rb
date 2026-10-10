Rails.application.routes.draw do
  # A topic key is its lesson's key (A1): kind, subject, slug.
  topic_key = /(ripasso|ponte|lezione)\.[a-z_]+\.[a-z0-9]+(-[a-z0-9]+)*/
  web = Banco::ListenerConstraint.new(:web)
  api = Banco::ListenerConstraint.new(:api)

  # Web listener: the student and the teacher, behind Traefik and Authelia.
  constraints(web) do
    get "up" => "rails/health#show", as: :rails_health_check
    # The front door (D-240): a student goes to Oggi, the teacher and a guest to /teacher, anyone else gets the 404.
    get "/" => "home#show", format: false
    get "teacher" => "teacher#show"

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
    get "settings" => "settings#show", format: false
    # The course of Phase 1b (A9): Oggi, the subjects, a topic, its lesson and its practice. Students only, official
    # and trial; the teacher and guests get 403. The official student sees nothing until release_course.
    scope format: false do
      topic = { topic: /(ripasso|ponte|lezione)\.[a-z_]+\.[a-z0-9]+(-[a-z0-9]+)*/ }
      get "today" => "course#today"
      get "subjects" => "course#subjects"
      get "subjects/:key" => "course#subject", constraints: { key: /[a-z_]+/ }
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
      post "questions" => "questions#create"
    end

    # The teacher's decisions (D-08): the only writes of DecisionRecorder. POST only,
    # ids in the path, everything else in the body.
    get "teacher/items/:revision_id" => "teacher/items#show", constraints: { revision_id: /\d+/ }, format: false
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

    # The teacher's pages (read-only) and the heartbeat of their minutes.
    scope "teacher", module: "teacher", format: false do
      key = { key: /[a-z_]+/ }
      get "subjects/:key/graph" => "graphs#show", constraints: key, as: :teacher_graph
      get "subjects/:key/test" => "tests#show", constraints: key, as: :teacher_test
      get "subjects/:key/test/all" => "tests#all", constraints: key, as: :teacher_test_all
      get "subjects/:key/test/skills/:skill" => "tests#skill", constraints: key.merge(skill: /[a-z0-9][a-z0-9.\-]*/), as: :teacher_test_skill
      get "subjects/:key/report" => "reports#show", constraints: key, as: :teacher_report
      get "subjects/:key/course" => "courses#show", constraints: key, as: :teacher_course
      get "subjects/:key/topics/:topic" => "topics#show", constraints: key.merge(topic: topic_key), as: :teacher_topic
      get "subjects/:key/practice" => "practice#show", constraints: key, as: :teacher_practice
      get "subjects/:key/practice/skills/:skill" => "practice#skill", constraints: key.merge(skill: /[a-z0-9][a-z0-9.\-]*/), as: :teacher_practice_skill
      get "corrections" => "corrections#show", as: :teacher_corrections
      get "refs/:key" => "refs#show", constraints: { key: /[a-z0-9][a-z0-9._-]*/ }, as: :teacher_ref
      get "items/:revision_id/play" => "item_plays#show", constraints: { revision_id: /\d+/ }, as: :teacher_item_play
      get "items/:revision_id/play/data" => "item_plays#data", constraints: { revision_id: /\d+/ }, as: :teacher_item_play_data
      post "activity" => "activity#create"
      # The box of a lesson/2 (R3, A14): the full body, a check graded with the seed "preview", a solution. Nothing is recorded.
      lr = { id: /\d+/ }
      n = /\d+/
      get "lesson-revisions/:id/full.json" => "lesson_revisions#full", constraints: lr, format: false
      post "lesson-revisions/:id/checks/:card/:block" => "lesson_revisions#check", constraints: lr.merge(card: n, block: n)
      post "lesson-revisions/:id/checks/:card/:block/:step" => "lesson_revisions#check", constraints: lr.merge(card: n, block: n, step: n)
      post "lesson-revisions/:id/checks/:card/:block/ex/:n" => "lesson_revisions#check", constraints: lr.merge(card: n, block: n, n: n)
      post "lesson-revisions/:id/checks/:card/:block/ex/:n/:part" => "lesson_revisions#check", constraints: lr.merge(card: n, block: n, n: n, part: n)
      post "lesson-revisions/:id/exercises/:n/solution" => "lesson_revisions#solution", constraints: lr.merge(n: n)
      post "topic-revisions/:revision_id/seen" => "seen#create", constraints: { revision_id: /\d+/ }, as: :teacher_topic_seen
    end

    scope "teacher/preview", as: :preview, defaults: { preview: true } do
      get "/" => "teacher/previews#index", as: :index
      post "runs/:run_id/close" => "sittings#close", as: :run_close
      concerns :sitting
    end

    # Figures drawn by agents: images only, named by their digest.
    get "assets/items/:sha256.svg" => "item_assets#show", constraints: { sha256: /[0-9a-f]{64}/ }, format: false
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
    get "api/v1/submissions/pending" => "api/v1/grades#pending", format: false
    post "api/v1/attempts/:attempt/grade-proposals" => "api/v1/grades#propose", constraints: { attempt: /\d+/ }, format: false

    # The author answers the findings (D-220); the teacher alone decides about them.
    post "api/v1/findings/:finding/responses" => "api/v1/findings#respond", constraints: { finding: /\d+/ }, format: false
    # The third reviewer reads a finding and says who is right (D-222); this too decides nothing.
    post "api/v1/findings/:finding/assessments" => "api/v1/findings#assess", constraints: { finding: /\d+/ }, format: false

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
    lesson = { lesson: /(ripasso|ponte|lezione)\.[a-z_]+\.[a-z0-9-]+/ }
    post "api/v1/lessons/submit" => "api/v1/lessons#submit", format: false
    get "api/v1/lessons/:lesson" => "api/v1/lessons#open", constraints: lesson, format: false
    get "api/v1/lesson-revisions/:revision" => "api/v1/lessons#status", constraints: revision, format: false
    get "api/v1/lesson-revisions/:revision/review" => "api/v1/lesson_reviews#open", constraints: revision, format: false
    post "api/v1/lesson-revisions/:revision/review" => "api/v1/lesson_reviews#submit", constraints: revision, format: false
    get "api/v1/topics/:topic" => "api/v1/topics#open", constraints: { topic: lesson[:lesson] }, format: false
    post "api/v1/topics/:topic" => "api/v1/topics#submit", constraints: { topic: lesson[:lesson] }, format: false
  end

  # Harness listener: the page and the files Chrome loads to run an agent's
  # generator or verify (A-02). Internal; never published.
  harness = Banco::ListenerConstraint.new(:harness)
  constraints(harness) do
    get "h/:token/:file" => "harness#show", constraints: { token: /[A-Za-z0-9_.-]+/, file: /harness\.html|runner\.mjs|generator\.mjs|verify\.mjs/ }, format: false
    get "lib/:file" => "harness#lib", constraints: { file: /rng\.mjs|fmt\.mjs/ }, format: false
  end

  # Everything else, including any route on the wrong listener: 404.
  match "*path", to: "not_found#show", via: :all
  root "not_found#show"
end
