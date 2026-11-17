module Attempts
  # The student's answers as the teacher bot reads them (D-346): three kinds in one list, oldest first.
  #
  #   practice   the guided practice's tries (Practice::AttemptLog): the engine's outcome, the hints, the serve
  #   diagnosis  the entry test's answers (Attempts::DiagnosisLog): the stored grading, the sitting, the shuffle
  #   lesson     the answers to the checks inside the lessons (Attempts::LessonLog): right or wrong, card and block
  #
  # A row has `kind`, `id` and `ref` ("practice-12"): the ref is what `detail` takes and what the list's cursor (`after`) is. A filter a kind cannot hold
  # leaves that kind out of the list. Read-only: nothing is written, nothing is recorded; teacher token only (Api::V1::AttemptsController).
  class Log
    KINDS = %w[practice diagnosis lesson].freeze
    DEFAULT_LIMIT = 100
    MAX_LIMIT = 500
    REF = /\A(#{KINDS.join('|')})-([1-9]\d{0,14})\z/
    # The values of the `outcome` filter: the practice engine's, the entry test's stored verdicts and a check's right or wrong.
    OUTCOMES = (Practice::AttemptLog::OUTCOMES + Grading::VERDICTS + %w[ungraded right wrong]).uniq.freeze

    # rows: the page of rows; total: how many answers match the filters; more: there are rows after the last one.
    Page = Data.define(:total, :rows, :more)

    # `after` is not a row of this list.
    class BadCursor < StandardError; end

    # [kind, id] of a ref ("practice-12", or a bare number, which is a practice try); nil when it is neither.
    def self.parse_ref(text)
      text = text.to_s
      return [ "practice", text.to_i ] if text.match?(/\A[1-9]\d{0,14}\z/)

      match = REF.match(text)
      match && [ match[1], match[2].to_i ]
    end

    def initialize(student)
      @student = student
      @sources = { "practice" => Practice::AttemptLog.new(student), "diagnosis" => DiagnosisLog.new(student), "lesson" => LessonLog.new(student) }
    end

    # kinds: the kinds to list (all by default); after: a ref (the last row of the previous page) or nil.
    def list(filters = Filters.new, kinds: KINDS, after: nil, limit: DEFAULT_LIMIT)
      entries = kinds.flat_map { |kind| @sources.fetch(kind).index(filters).map { |id, at| [ at, kind, id ] } }
      entries.sort_by! { |at, kind, id| [ at, KINDS.index(kind), id ] }
      rows = nil
      if filters.outcome
        rows = rows_for(entries, filters).select { |r| r[:outcome] == filters.outcome }
        entries = rows.map { |r| [ nil, r[:kind], r[:id] ] }
      end
      total = entries.size
      entries = after_cursor(entries, after) if after
      shown = entries.first(limit)
      rows = rows ? rows.select { |r| shown.any? { |_, kind, id| kind == r[:kind] && id == r[:id] } } : rows_for(shown, filters)
      Page.new(total: total, rows: rows, more: entries.size > limit)
    end

    # The detail of a ref's answer, or nil when it is not this student's. comment: a Comment to keep alone among the comments next to it.
    def detail(kind, id, comment: nil)
      found = @sources.fetch(kind).detail(id, comment: comment) or return nil
      head = { kind: kind, ref: "#{kind}-#{id}" }
      head.merge(found).merge(attempt: head.merge(found[:attempt]))
    end

    private

    def after_cursor(entries, ref)
      kind, id = self.class.parse_ref(ref)
      at = kind && entries.index { |_, k, i| k == kind && i == id }
      raise BadCursor unless at

      entries.drop(at + 1)
    end

    # The rows of the entries, in the order of the entries: one query set per kind.
    def rows_for(entries, filters)
      by_kind = entries.group_by { |_, kind, _| kind }
      found = by_kind.to_h { |kind, list| [ kind, @sources.fetch(kind).rows(list.map(&:last), filters).index_by { |r| r[:id] } ] }
      entries.filter_map do |_, kind, id|
        row = found.fetch(kind)[id] or next
        { kind: kind, ref: "#{kind}-#{id}" }.merge(row)
      end
    end
  end
end
