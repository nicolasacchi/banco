module Api
  module V1
    # GET /api/v1/search?q=WORDS[&subject=KEY][&kind=KIND[,KIND]][&status=S][&limit=N]: the content search for the agents (D-299).
    # Drafts included, every subject; never an answer key. Never anything a student typed either (the kind student_answer is not a kind of
    # this door), except for a `teacher` token (D-346): kind=student_answer, with student=KEY (default: the official student), searches that
    # student's answers as the teacher console's answers tab does (lexical only, no model); a row of it has student, at and, for a practice try or an
    # entry-test answer, attempt (its ref: banco attempts show REF). Without kind=student_answer a teacher token's search is the content search, as for every token.
    # Read only. `semantic` says whether the ranking used vectors (D-300): false whenever the embedding service
    # is not configured or does not answer, and then the answer is the lexical one.
    #
    #   { query:, semantic:, indexed:, results: [{ kind:, subject:, key:, revision_id:, status:, title:, snippet:, score:, ref: }] }
    #
    # GET /api/v1/search?like=KEY (or kind:KEY#anchor, as `ref` writes it; lesson:KEY for a whole lesson, lesson_card:KEY#N for its card
    # N) is "Simili": the nearest neighbours of an object, from the vectors already stored, the object itself left out; a row of another
    # document of the same key (the other instances of an item, the other cards of a lesson) has `same_object: true`, a row of a whole
    # lesson's neighbours has `near:` (the lesson's card it is nearest to). The answer has `like:` (the object found) and, when the object
    # or some of its cards have no vector yet, `waiting:` (documents waiting for one) and a `note`; with none at all, `semantic: false`
    # and no results (D-315).
    class SearchController < Api::BaseController
      DEFAULT_LIMIT = 20
      MAX_LIMIT = 50

      def show
        return like if params[:like].present?

        query = params[:q].to_s.squish.first(300)
        return refuse("E-FILES", "q", "give the words to search for: banco search QUERY", "banco search \"equazioni\"", 422) if query.empty?

        subject = params[:subject].to_s.presence
        if subject && !Subject.exists?(key: subject)
          return refuse("E-NOT-FOUND", "subject", "no subject #{subject.first(40).inspect}", "banco status", 404)
        end

        kinds = params[:kind].to_s.split(",").map(&:strip).reject(&:empty?)
        limit = [ [ params[:limit].to_i, 1 ].max, MAX_LIMIT ].min if params[:limit].present?
        scope = scope_for(kinds) or return
        result = Search::Engine.new(scope: scope).call(query, subject: subject, kind: kinds, status: params[:status].to_s.presence, limit: limit || DEFAULT_LIMIT)
        render json: { query: result.query, semantic: result.semantic, indexed: result.indexed, results: result.hits.map { |hit| row(hit, result) } }
      rescue Search::Engine::BadKind => e
        refuse("E-NOT-FOUND", "kind", "no kind #{e.message.first(40).inspect} for agents; kinds: #{visible_kinds.join(', ')}",
               "banco search \"equazioni\" --kind lesson_card", 404)
      end

      private

      # The agents' scope; a teacher token that asks for kind=student_answer gets the teacher console's answers of one student (D-346). nil after answering 404.
      def scope_for(kinds)
        return Search::Scope::Agent.new unless @token.role == "teacher" && kinds.include?("student_answer")

        key = params[:student].to_s.presence || Student::OFFICIAL_KEY
        student = Student::KEY_FORMAT.match?(key) ? Student.find_by(key: key, kind: "student") : nil
        return Search::Scope::Agent.new(answers_for: student.key) if student

        refuse("E-NOT-FOUND", "student", "no student #{key.first(40).inspect}", "banco search \"words\" --kind student_answer --student student", 404)
        nil
      end

      # The kinds this token may ask for: the content kinds, and for a teacher token student_answer.
      def visible_kinds = Search::Scope::Agent.new(answers_for: (@token.role == "teacher" ? "-" : nil)).kinds

      def like
        ref = params[:like].to_s.squish.first(200)
        subject = params[:subject].to_s.presence
        if subject && !Subject.exists?(key: subject)
          return refuse("E-NOT-FOUND", "subject", "no subject #{subject.first(40).inspect}", "banco status", 404)
        end

        kinds = params[:kind].to_s.split(",").map(&:strip).reject(&:empty?)
        limit = [ [ params[:limit].to_i, 1 ].max, MAX_LIMIT ].min if params[:limit].present?
        result = Search::Engine.new(scope: Search::Scope::Agent.new).like(ref, subject: subject, kind: kinds, status: params[:status].to_s.presence, limit: limit || DEFAULT_LIMIT)
        unless result.source
          return refuse("E-NOT-FOUND", "like", "no document with the key #{ref.first(60).inspect}",
                        "banco search \"words of it\" (its ref is in every result; a whole lesson is lesson:KEY, its card N lesson_card:KEY#N)", 404)
        end

        body = { query: ref, like: Search::Links.address(result.source), semantic: result.semantic, indexed: result.indexed,
                 results: result.hits.map { |hit| like_row(hit, result) } }
        if result.missing.positive?
          body[:waiting] = Search::Vectors.waiting(Search::Embedder.current)
          body[:note] = like_note(result, body[:waiting])
        end
        render json: body
      rescue Search::Engine::SemanticOff
        refuse("E-NOT-FOUND", "like", "similar objects need the embedding service (BANCO_EMBED_URL), which is not set up", "banco search \"words\"", 404)
      rescue Search::Engine::BadKind => e
        refuse("E-NOT-FOUND", "kind", "no kind #{e.message.first(40).inspect} for agents; kinds: #{Search::Scope::Agent.new.kinds.join(', ')}",
               "banco search --like KEY --kind item", 404)
      end

      # A neighbour: same_object for another document of the same key; near (a whole lesson) the address of the lesson's nearest card.
      def like_row(hit, result)
        row = row(hit, result).merge(same_object: hit.key == result.source.key)
        hit.near ? row.merge(near: hit.near) : row
      end

      # Why some or all of the object's documents have no neighbours yet (D-315): they wait for the embedding job.
      def like_note(result, waiting)
        queue = "#{waiting} document#{'s' unless waiting == 1} of the index wait#{'s' if waiting == 1} for a vector; a new or changed document gets one " \
                "within minutes of its submit: run --like again later"
        if result.semantic
          "#{result.missing} of the #{result.members} cards of this lesson have no vector yet, the neighbours are those of the others: #{queue}"
        else
          "no vectors yet for this object: #{queue}"
        end
      end

      def row(hit, result)
        out = { kind: hit.kind, subject: hit.subject, key: hit.key, revision_id: hit.revision_id, status: hit.status, title: hit.title,
                snippet: hit.snippet(result.terms, result.variants), score: hit.score.round(3), ref: Search::Links.address(hit) }
        hit.kind == "student_answer" ? out.merge(answer_row(hit)) : out
      end

      # The student's answer of a hit (a teacher token only ever sees one): whose, when and, for a practice try (anchor pN) or an entry-test answer
      # (anchor aN), the ref `banco attempts show` takes. A refused text (anchor eN) is no attempt.
      def answer_row(hit)
        kind = { "p" => "practice", "a" => "diagnosis" }[hit.anchor.to_s[0]]
        number = hit.anchor.to_s[/\A[pa](\d+)\z/, 1]
        { student: hit.student_key, at: hit.occurred_at, attempt: kind && number && "#{kind}-#{number}" }.compact
      end
    end
  end
end
