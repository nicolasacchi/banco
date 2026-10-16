module Search
  module Builders
    # Lesson cards and glossary terms of the live lesson revisions. The text is what the student is served and nothing else:
    # a banco.lesson/2 body goes through Lessons::StudentBody (the whitelist), a banco.lesson/1 body contributes its sections and
    # the statements of the exercises, never their solutions or final answers.
    module Lessons
      SECTION_KEYS = %w[why_it idea_it example_it mistakes_it book_it summary_it].freeze

      module_function

      def call
        topics = Live.topic_revisions
        approved = topics.select { |t| Live.approved_topic_revision_ids.include?(t.id) }.to_set(&:lesson_revision_id)
        Live.lesson_revisions(topics).flat_map { |revision| docs_of(revision, approved.include?(revision.id) ? "approved" : (revision.reviews.exists? ? "reviewed" : "draft")) }
      end

      def docs_of(revision, status)
        body = revision.body
        subject = revision.lesson.subject.key
        context = { key: revision.lesson.key, subject: subject, revision_table: "lesson_revisions", revision_id: revision.id, status: status,
                    lang: ::Lessons::Lang.target(subject) || "it", topic_key: revision.lesson.key }
        title = body["title_it"].to_s
        docs = body["schema"] == "banco.lesson/2" ? lesson2(body, revision, title, context) : lesson1(body, title, context)
        docs + glossary(body, title, context)
      end

      def lesson2(body, revision, title, context)
        student = ::Lessons::StudentBody.project(body, revision_id: revision.id, seed: "search")
        cover = Doc.build(kind: "lesson_card", title: title, body: Text.join(Text.strings(student.slice("goals_it", "why_it"))), anchor: nil, **context)
        cards = student["cards"].map do |card|
          Doc.build(kind: "lesson_card", title: Text.plain(card["title_it"]), anchor: "scheda-#{card['n']}",
                    body: Text.join(Text.plain(card["short_it"]), Text.strings(card["blocks"])), **context)
        end
        [ cover ] + cards
      end

      def lesson1(body, title, context)
        sections = SECTION_KEYS.filter_map do |name|
          text = body.dig("sections", name).presence or next
          Doc.build(kind: "lesson_card", title: "#{title} · #{I18n.t("search.sections.#{name}")}", body: Text.plain(text), unique: name, **context)
        end
        exercises = Array(body["exercises"]).filter_map { |e| Text.plain(e["text_it"]).presence }
        intro = Text.plain(body["try_intro_it"])
        unless exercises.empty?
          sections << Doc.build(kind: "lesson_card", title: "#{title} · #{I18n.t('search.sections.try')}", body: Text.join(intro, exercises), unique: "try", **context)
        end
        sections
      end

      # A term of the lesson's glossary; the anchor is the first card that marks the term ([[g:term]]).
      def glossary(body, title, context)
        Array(body["glossary"]).filter_map do |entry|
          term = entry["term_it"].to_s.strip.presence or next
          Doc.build(kind: "glossary_term", title: term, body: Text.join(Text.plain(entry["def_it"]), Text.plain(entry["example_it"]), Array(entry["synonyms_it"]).join(" ")),
                    anchor: card_of(body, term), unique: term, **context)
        end
      end

      def card_of(body, term)
        marker = "[[g:#{term.downcase}]]"
        card = Array(body["cards"]).find { |c| JSON.generate(c).downcase.include?(marker) }
        card && "scheda-#{card['n']}"
      end
    end
  end
end
