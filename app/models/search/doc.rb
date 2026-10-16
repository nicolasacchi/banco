module Search
  # One searchable unit before it is written: the builders return these, Search::Index stores them.
  #
  # audience says which doors may ever read the row: "student" (what a student's page shows: the text is the whitelist
  # the student is served), "staff" (the teacher, guests and agents) or "teacher" (the student's answers: the teacher only).
  # It is fixed by the kind; who may see which revision is decided at query time (Search::Scope).
  Doc = Data.define(:kind, :key, :title, :body, :subject, :revision_table, :revision_id, :status, :anchor, :lang, :topic_key, :skill,
                    :student_key, :occurred_at, :unique) do
    def self.build(kind:, key:, title:, body:, subject: nil, revision_table: nil, revision_id: nil, status: nil, anchor: nil, lang: "it", topic_key: nil,
                   skill: nil, student_key: nil, occurred_at: nil, unique: nil)
      raise ArgumentError, "unknown kind #{kind}" unless Doc::KINDS.include?(kind)

      new(kind: kind, key: key, title: title.to_s.squish.first(300), body: body.to_s.strip, subject: subject, revision_table: revision_table,
          revision_id: revision_id, status: status, anchor: anchor&.to_s, lang: lang, topic_key: topic_key, skill: skill, student_key: student_key,
          occurred_at: occurred_at&.to_s, unique: unique&.to_s)
    end

    def audience
      return "student" if Doc::STUDENT_KINDS.include?(kind)

      Doc::TEACHER_KINDS.include?(kind) ? "teacher" : "staff"
    end

    # What makes this row the same row on the next build.
    def doc_key = [ kind, key, revision_id, anchor, student_key, unique ].join("|")

    # The langs whose stems the row carries: Italian, and the language the subject teaches.
    def stem_langs = ([ "it" ] + [ lang ]).uniq

    def digest = Digest::SHA256.hexdigest([ title, body, subject, revision_table, revision_id, status, anchor, lang, topic_key, skill, occurred_at ].join("\u0001"))
  end

  Doc::STUDENT_KINDS = %w[lesson_card glossary_term topic practice_item].freeze
  Doc::STAFF_KINDS = %w[course skill item item_instance reference_article syllabus_line finding].freeze
  Doc::TEACHER_KINDS = %w[student_answer].freeze
  Doc::KINDS = (Doc::STUDENT_KINDS + Doc::STAFF_KINDS + Doc::TEACHER_KINDS).freeze
end
