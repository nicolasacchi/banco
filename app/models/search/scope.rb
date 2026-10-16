module Search
  # Who may read which documents, decided when the question is asked, from the same code the pages use. The index holds
  # revisions and texts; it never holds a "visible" flag that could go stale. A scope gives:
  #
  #   kinds      the document kinds this door can ever return (a kind outside it is refused, not silently dropped)
  #   audiences  the audience classes of those kinds (Search::Doc#audience): a second lock on the same door
  #   clause     [sql, binds] over search_documents aliased `d`
  #
  #   Scope::Student  a student's door: the revisions the catalog (Course::Catalog) shows this student, the kinds a student page shows
  #   Scope::Staff    the teacher's and the guests' door; the teacher's may include the student's answers
  #   Scope::Agent    the agents' door (API): content only, never anything a student typed
  class Scope
    attr_reader :name

    def kinds = raise(NotImplementedError)
    def audiences = raise(NotImplementedError)
    def clause = raise(NotImplementedError)

    # Whether the ranking may use vectors (S2): never for a student (firm rule 1: no model in the student's path).
    def semantic? = false

    # [sql, binds] shared by every scope: kinds and audience, so a scope can only narrow.
    def base_clause
      [ "d.kind IN (#{kinds.map { '?' }.join(', ')}) AND d.audience IN (#{audiences.map { '?' }.join(', ')})", kinds + audiences ]
    end

    def self.in_list(ids) = ids.empty? ? "(NULL)" : "(#{ids.map { |i| Integer(i) }.join(', ')})"

    # Nothing matches.
    class Nothing < Scope
      def kinds = []
      def audiences = []
      def clause = [ "0 = 1", [] ]
    end

    # A student's door (D-299). The visible revisions are those of Course::StudentView.new(student): an official student has the
    # approved topics of a released course, a trial student the latest topics of the latest map (D-217), a teacher's preview and a
    # teacher nothing. Kinds: lesson cards, glossary terms, topics and the practice items of those topics (the stem and options
    # Items::Part serves). A diagnosis item is never a practice item: only items of kind practice_item are indexed as such, and the
    # clause asks the primary database again for the kind of each pinned revision.
    class Student < Scope
      KINDS = %w[lesson_card glossary_term topic practice_item].freeze

      attr_reader :student

      def self.for(student)
        student && student.kind == "student" ? new(student) : Nothing.new
      end

      def initialize(student)
        @student = student
        @name = :student
      end

      def kinds = KINDS
      def audiences = %w[student]

      # Stated here as well as in the base class: a change to the default can never switch a model on in the student's path.
      def semantic? = false

      def view = @view ||= Course::StudentView.new(student)

      def topics = @topics ||= view.subjects.flat_map(&:topics)

      def lesson_revision_ids = topics.map { |t| t.lesson_revision.id }.uniq
      def topic_revision_ids = topics.map { |t| t.topic_revision.id }.uniq

      # {item revision id => [topic key, skill]} for the practice items pinned by the topics this student sees (the first topic wins).
      def practice_targets
        @practice_targets ||= begin
          pins = topics.flat_map do |topic|
            Array(topic.topic_revision.body["practice"]).flat_map { |p| Array(p["items"]).map { |i| [ i["revision"], topic.key, p["skill"] ] } }
          end
          practice = ItemRevision.joins(:item).where(id: pins.map(&:first), items: { kind: Item::PRACTICE_KINDS }).pluck(:id).to_set
          pins.select { |id, _, _| practice.include?(id) }.each_with_object({}) { |(id, topic, skill), out| out[id] ||= [ topic, skill ] }
        end
      end

      def clause
        base, binds = base_clause
        [ "#{base} AND ((d.revision_table = 'lesson_revisions' AND d.kind IN ('lesson_card', 'glossary_term') AND d.revision_id IN #{Scope.in_list(lesson_revision_ids)}) " \
          "OR (d.revision_table = 'topic_revisions' AND d.kind = 'topic' AND d.revision_id IN #{Scope.in_list(topic_revision_ids)}) " \
          "OR (d.revision_table = 'item_revisions' AND d.kind = 'practice_item' AND d.revision_id IN #{Scope.in_list(practice_targets.keys)}))", binds ]
      end
    end

    # The teacher's and the guests' door, and the agents' (Agent narrows it): every status, the latest revision of each object.
    # answers: the teacher only (never a guest, never an agent) may ask for the kind student_answer, for one student.
    class Staff < Scope
      attr_reader :answers_for

      def initialize(answers_for: nil)
        @name = answers_for ? :teacher : :staff
        @answers_for = answers_for
      end

      def kinds = Doc::STUDENT_KINDS + Doc::STAFF_KINDS + (answers_for ? Doc::TEACHER_KINDS : [])
      def audiences = answers_for ? %w[student staff teacher] : %w[student staff]

      def clause
        base, binds = base_clause
        latest = Latest.all.map { |table, ids| "(d.revision_table = '#{table}' AND d.revision_id IN #{Scope.in_list(ids)})" }
        sql = "#{base} AND (d.revision_table IS NULL OR #{latest.join(' OR ')})"
        if answers_for
          sql += " AND (d.kind <> 'student_answer' OR d.student_key = ?)"
          binds += [ answers_for.to_s ]
        end
        [ sql, binds ]
      end
    end

    # The agents' door: the content of the courses and the references, drafts included; nothing a student typed.
    class Agent < Staff
      def initialize
        super(answers_for: nil)
        @name = :agent
      end
    end
  end
end
