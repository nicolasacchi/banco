module Api
  module V1
    # The author's side of the findings (D-220). A finding of a review or a blind solve is a
    # possible problem; the teacher decides who is right, in the browser. Here the author reads
    # the blocker and major findings of a subject and answers each one: the item is right (with a
    # short proof) or a later revision fixes it. A response never disposes of a finding.
    #
    # A finding of a lesson review (D-313) is answered the same way: its id is L<review>-<n> (LessonFindings),
    # the stance lesson_right or fixed (a later revision of the same lesson), and the answer disposes of nothing:
    # the teacher approves the topic or sends the lesson back, in the browser.
    #
    # The third reviewer, the arbiter (D-222), reads a finding with the item and the author's answer and
    # says who is right. Two opinions count, the first and the second (two models), and the second must
    # be written independently: an arbiter session does not see the assessments of a finding before it has
    # written its own. An assessment never writes a decision: the teacher decides, in the browser.
    class FindingsController < Api::BaseController
      include IndependentRoles

      KEYS = %w[stance revision_id note_it].freeze
      ASSESS_KEYS = %w[verdict note_it].freeze
      KINDS = %w[item lesson].freeze
      NEW_AUTHOR = "banco session new --role author --agent NAME --model MODEL".freeze

      # GET /api/v1/subjects/:subject/findings[?open=1][&all=1][&kind=item|lesson][&lesson=KEY][&topic=KEY]
      # Blocker and major findings of the subject (all=1: minor ones too, for the third reviewer), newest revision last, with the teacher's
      # disposition, the latest response of the author and the third reviewer's opinion (the first and the second assessment). The assessments are shown only to a valid
      # session that is not an arbiter still to assess that finding (else a count only). open=1: no disposition yet, no response yet,
      # and on the current or a pinned revision (not a superseded one).
      #
      # The rows of the items come first (kind item), then those of the lesson reviews (kind lesson, D-313: id L<review>-<n>, the lesson,
      # the revision, the card or section, the teacher's decision on the lesson, the latest response; open=1: no decision, no response, on
      # the current revision or the one the latest topic revision pins). kind keeps one of the two; lesson=KEY keeps the findings of that
      # lesson; topic=KEY those of the topic's lesson and of the items its latest revision pins.
      def index
        subject = Subject.find_by(key: params[:subject].to_s)
        return refuse("E-NOT-FOUND", "subject", "no subject #{params[:subject].to_s.first(40).inspect}", "banco status", 404) unless subject

        kind = params[:kind].to_s
        unless kind.empty? || KINDS.include?(kind)
          return refuse("E-NOT-FOUND", "kind", "kind is item or lesson, not #{kind.first(40).inspect}", "banco findings list --subject #{subject.key} --kind lesson", 404)
        end
        lesson = filter_lesson(subject, :lesson) or return
        topic = filter_lesson(subject, :topic) or return

        open = params[:open].to_s.in?(%w[1 true])
        all = params[:all].to_s.in?(%w[1 true])
        rows = []
        rows.concat(item_rows(subject, all: all, open: open, topic: topic.presence)) if kind != "lesson" && lesson.blank?
        rows.concat(lesson_rows(subject, keys: [ lesson, topic ].compact_blank.map(&:key).uniq, all: all, open: open)) if kind != "item"
        render json: { subject: subject.key, rows: rows,
                       next: "answer each open row: banco findings respond FINDING_ID --file response.json (an item: banco brief show diagnosis-item; a lesson: banco brief show lesson)" }
      end

      # POST /api/v1/findings/:id/responses {response: {stance, revision_id?, note_it}}
      def respond
        return respond_lesson if LessonFindings::ID.match?(params[:finding].to_s)

        finding = ReviewFinding.find_by(id: params[:finding])
        return refuse("E-NOT-FOUND", "finding", "no finding #{params[:finding].to_s.first(20).inspect}", "banco findings list --subject SUBJECT", 404) unless finding

        body = parse_json_body or return
        item = finding.item_revision.item
        session = require_session("author", item: item, next_step: NEW_AUTHOR) or return
        return unless allowed_author?(session, finding, item)

        doc = body["response"]
        return refuse("E-FILES", "response", "send the answer as {response: {...}}", next_step(finding), 422) unless doc.is_a?(Hash)

        ok, revision = checked_revision(doc, finding, item)
        return unless ok

        note = doc["note_it"]
        return unless checked_note(note, FindingResponse::MAX_NOTE, "response", next_step(finding))
        return render json: { dry_run: true, status: "passed", codes: [] } if dry_run?

        row = FindingResponse.create!(review_finding: finding, agent_session: session, stance: doc["stance"], item_revision: revision, note_it: note.strip)
        render json: row.to_h.merge(disposition: finding.disposition,
                                    next: "stop here: only the teacher decides about the finding, in the browser (banco status)"), status: :created
      end

      # POST /api/v1/findings/:id/assessments {assessment: {verdict, note_it}}
      def assess
        finding = ReviewFinding.find_by(id: params[:finding])
        return refuse("E-NOT-FOUND", "finding", "no finding #{params[:finding].to_s.first(20).inspect}", "banco findings list --subject SUBJECT --all", 404) unless finding

        body = parse_json_body or return
        item = finding.item_revision.item
        session = require_session("arbiter", item: item, finding: finding, next_step: "banco session new --role arbiter --agent NAME --model MODEL") or return
        return unless allowed_arbiter?(session, item)

        doc = body["assessment"]
        step = assess_step(finding)
        return refuse("E-FILES", "assessment", "send the opinion as {assessment: {verdict, note_it}}", step, 422) unless doc.is_a?(Hash)

        extra = doc.keys - ASSESS_KEYS
        return refuse("E-FILES", "assessment/#{extra.first}", "the opinion has only #{ASSESS_KEYS.join(', ')}", step, 422) if extra.any?
        return refuse("E-FILES", "assessment/verdict", "verdict is #{FindingAssessment::VERDICTS.join(', ')}", step, 422) unless FindingAssessment::VERDICTS.include?(doc["verdict"])
        return unless checked_note(doc["note_it"], FindingAssessment::MAX_NOTE, "assessment", step)
        return render json: { dry_run: true, status: "passed", codes: [] } if dry_run?

        row = FindingAssessment.create!(review_finding: finding, agent_session: session, verdict: doc["verdict"], note_it: doc["note_it"].strip)
        render json: row.to_h.merge(next: "stop here: the teacher decides, in the browser; the second opinion is another model's job"), status: :created
      end

      private

      # The rows of the item findings: the subject's, or those of the items the topic's latest revision pins.
      def item_rows(subject, all:, open:, topic: nil)
        scope = all ? ReviewFinding.all : ReviewFinding.must_be_disposed
        scope = scope.joins(item_revision: :item).where(items: { subject_id: subject.id })
        scope = scope.where(item_revisions: { item_id: topic_item_ids(topic) }) if topic
        findings = scope.includes(item_revision: :item).order(:id).to_a
        dispositions = ReviewFinding.dispositions
        responses = FindingResponse.latest_for(findings.map(&:id))
        opinions = FindingAssessment.opinions_for(findings.map(&:id))
        viewer = viewer_session
        latest = Item.where(subject: subject).includes(:revisions).to_h { |i| [ i.id, i.revisions.map(&:seq).max ] }
        pinned = BlueprintRevision.where(subject: subject).order(:seq).last&.pinned_item_revision_ids.to_a
        rows = findings.map do |f|
          rev = f.item_revision
          { finding_id: f.id, kind: "item", item: rev.item.key, item_kind: rev.item.kind, revision_id: rev.id, seq: rev.seq, current: rev.seq == latest[rev.item_id],
            severity: f.severity, source: f.source, instance: f.instance, problem_it: f.problem_it, fix_it: f.fix_it,
            disposition: dispositions[f.id], response: responses[f.id]&.to_h, opinion: visible_opinion(opinions[f.id], viewer) }.compact
        end
        open ? rows.select { |r| r[:disposition].nil? && r[:response].nil? && (r[:current] || pinned.include?(r[:revision_id])) } : rows
      end

      # The rows of the lesson findings (D-313). keys: none for every lesson, one key for that lesson, two different keys
      # (a lesson and another topic) for none.
      def lesson_rows(subject, keys:, all:, open:)
        return [] if keys.size > 1

        rows = LessonFindings.rows(subject, keys: keys.presence, all: all)
        open ? rows.select { |r| r[:decision].nil? && r[:response].nil? && (r[:current] || r[:pinned]) } : rows
      end

      # The items whose revisions the latest revision of the topic pins (none when it has no revision yet).
      def topic_item_ids(lesson)
        revision = lesson.topic_revisions.max_by(&:seq) or return []
        ItemRevision.where(id: Approval::TopicGate.item_revision_ids(revision)).distinct.pluck(:item_id)
      end

      # The lesson named by params[name] (lesson or topic: the topic is its lesson): "" when the parameter is
      # absent, nil once a 404 has been answered.
      def filter_lesson(subject, name)
        key = params[name].to_s
        return "" if key.empty?

        lesson = Lesson.find_by(subject: subject, key: key)
        return lesson if lesson

        refuse("E-NOT-FOUND", name.to_s, "no #{name} #{key.first(80).inspect} in #{subject.key}", "banco #{name == :topic ? 'topics' : 'lessons'} list --subject #{subject.key}", 404)
        nil
      end

      def next_step(finding) = "banco findings respond #{finding.id} --file response.json"

      # A lesson finding (D-313): the rules of an item finding, on the lesson.
      def respond_lesson
        entry = LessonFindings.find(params[:finding])
        return refuse("E-NOT-FOUND", "finding", "no lesson finding #{params[:finding].to_s.first(24).inspect}", "banco findings list --subject SUBJECT --kind lesson", 404) unless entry

        body = parse_json_body or return
        base = entry.review.lesson_revision
        lesson = base.lesson
        session = require_session("author", item: lesson, next_step: NEW_AUTHOR) or return
        return unless allowed_lesson_author?(session, entry, lesson)

        doc = body["response"]
        return refuse("E-FILES", "response", "send the answer as {response: {...}}", next_step(entry), 422) unless doc.is_a?(Hash)

        ok, revision = checked_lesson_revision(doc, entry, base)
        return unless ok

        note = doc["note_it"]
        return unless checked_note(note, LessonFindingResponse::MAX_NOTE, "response", next_step(entry))
        return render json: { dry_run: true, status: "passed", codes: [] } if dry_run?

        row = LessonFindingResponse.create!(lesson_review: entry.review, finding_n: entry.n, agent_session: session, stance: doc["stance"],
                                            lesson_revision: revision, note_it: note.strip)
        render json: row.to_h.merge(kind: "lesson", lesson: lesson.key, decision: LessonFindings.decision(base),
                                    next: "stop here: only the teacher decides, when she approves the topic or sends the lesson back, in the browser (banco status)"),
               status: :created
      end

      # An author-role session that did not raise the finding and holds no other role on the item.
      def allowed_author?(session, finding, item)
        if finding.raised_by_session_id == session.id
          refuse("E-SESSION-NOT-INDEPENDENT", "X-Banco-Session", "session #{session.id} raised finding #{finding.id}: the author must be another session", NEW_AUTHOR, 422)
          return false
        end
        held = ItemSessions.new(item).conflicts(session.id, "author")
        return true if held.empty?

        refuse("E-SESSION-NOT-INDEPENDENT", "X-Banco-Session", "session #{session.id} already acted as #{held.join(' and ')} on #{item.key}: the author must be another session", NEW_AUTHOR, 422)
        false
      end

      # An author-role session that did not write the review and holds no other role on the lesson.
      def allowed_lesson_author?(session, entry, lesson)
        if entry.review.agent_session_id == session.id
          refuse("E-SESSION-NOT-INDEPENDENT", "X-Banco-Session", "session #{session.id} raised finding #{entry.id}: the author must be another session", NEW_AUTHOR, 422)
          return false
        end
        held = LessonSessions.new(lesson).conflicts(session.id, "author")
        return true if held.empty?

        refuse("E-SESSION-NOT-INDEPENDENT", "X-Banco-Session", "session #{session.id} already acted as #{held.join(' and ')} on #{lesson.key}: the author must be another session", NEW_AUTHOR, 422)
        false
      end

      # [ok, revision]: the revision of a fixed answer (nil for item_right). On a problem it answers 422 and ok is false.
      def checked_revision(doc, finding, item)
        extra = doc.keys - KEYS
        return bad("response/#{extra.first}", "the answer has only #{KEYS.join(', ')}", finding) if extra.any?

        stance = doc["stance"]
        return bad("response/stance", "stance is item_right or fixed", finding) unless FindingResponse::STANCES.include?(stance)

        raw = doc["revision_id"]
        if stance == "item_right"
          return [ true, nil ] if raw.nil?

          return bad("response/revision_id", "item_right has no revision_id", finding)
        end
        id = raw.to_s
        revision = ItemRevision.find_by(id: id) if id.match?(AgentSession::ID)
        unless revision && revision.item_id == item.id && revision.seq > finding.item_revision.seq
          return bad("response/revision_id", "fixed needs revision_id: a later revision of #{item.key} than revision #{finding.item_revision.id} (seq #{finding.item_revision.seq})",
                     finding, "banco items list --subject #{item.subject.key} --current")
        end
        [ true, revision ]
      end

      # [ok, revision] for a lesson finding: lesson_right has no revision, fixed names a later revision of the same lesson.
      def checked_lesson_revision(doc, entry, base)
        extra = doc.keys - KEYS
        return bad("response/#{extra.first}", "the answer has only #{KEYS.join(', ')}", entry) if extra.any?

        stance = doc["stance"]
        unless LessonFindingResponse::STANCES.include?(stance)
          return bad("response/stance", "the stance of a lesson finding is lesson_right or fixed#{' (item_right is for the findings of an item)' if stance == 'item_right'}", entry)
        end

        raw = doc["revision_id"]
        if stance == "lesson_right"
          return [ true, nil ] if raw.nil?

          return bad("response/revision_id", "lesson_right has no revision_id", entry)
        end
        id = raw.to_s
        revision = LessonRevision.find_by(id: id) if id.match?(AgentSession::ID)
        unless revision && revision.lesson_id == base.lesson_id && revision.seq > base.seq
          return bad("response/revision_id", "fixed needs revision_id: a later revision of #{base.lesson.key} than revision #{base.id} (seq #{base.seq})",
                     entry, "banco lessons list --subject #{base.lesson.subject.key}")
        end
        [ true, revision ]
      end

      def bad(field, message, finding, next_step = next_step(finding))
        refuse("E-FILES", field, message, next_step, 422)
        [ false, nil ]
      end

      def checked_note(note, max, doc_name, step)
        unless note.is_a?(String) && !note.strip.empty? && note.strip.size <= max
          refuse("E-FILES", "#{doc_name}/note_it", "note_it is a text of 1 to #{max} characters", step, 422)
          return false
        end
        findings = Validation::Findings.new
        Validation::Readability.lint_document({ "note_it" => note }, doc_name, findings)
        return true unless refuse_findings(findings, "shorten and simplify note_it, then #{step}")

        false
      end

      def assess_step(finding) = "banco findings assess #{finding.id} --file assessment.json"

      # An arbiter session that holds no other role on the item. Judging many findings of one item is fine.
      def allowed_arbiter?(session, item)
        held = ItemSessions.new(item).conflicts(session.id, "arbiter")
        return true if held.empty?

        refuse("E-SESSION-NOT-INDEPENDENT", "X-Banco-Session", "session #{session.id} already acted as #{held.join(' and ')} on #{item.key}: the arbiter must be another session",
               "banco session new --role arbiter --agent NAME --model MODEL", 422)
        false
      end

      # The session of the request when it is a valid one of this token, else nil (no error answered).
      def viewer_session
        raw = request.headers["X-Banco-Session"].to_s
        session = AgentSession.find_by(id: raw) if raw.match?(AgentSession::ID)
        session if session && (session.token_id.nil? || session.token_id == @token.id)
      end

      # The opinion on a finding as the viewer may read it (D-222). The second opinion is written
      # independently, so the assessments go only to a valid session of this token that is not an
      # arbiter still to assess this finding: the author, a reviewer or operator session, or an arbiter that
      # has assessed it itself. Without a valid session, or for an arbiter that has not assessed it, only
      # the count of the opinions given is shown.
      def visible_opinion(opinion, viewer)
        return nil unless opinion.any?
        return { hidden: true, count: opinion.given.size } if viewer.nil? || (viewer.role == "arbiter" && opinion.given.none? { |a| a.agent_session_id == viewer.id })

        { state: opinion.state, verdict: opinion.verdict, first: opinion.first&.to_h, second: opinion.second&.to_h }.compact
      end
    end
  end
end
