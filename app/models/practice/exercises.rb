module Practice
  # The list of the exercises of a topic for one student (D-337): what the practice page draws as a sidebar. Per skill of the topic, the items
  # pinned on the topic revision this student sees, in pin order, each with its status from the student's serves. Read-only.
  #
  #   status, in this order: "unfinished" when the open serve has a non-empty draft and no try (typed, not answered: «Da finire»);
  #           "done" when any serve of the item closed correct; "contested" when no serve is open and one closed `contested` (he sent it to the teacher with
  #           «Per me va bene così», D-389: «Mandato al docente»); "finished_solution" when a serve with a try or a shown solution ended (closed,
  #           abandoned, or still open with a try) and the STUDENT asked for the solution (an event `solution_shown` with the reason
  #           `requested`, or `after_wrong` on a serve already closed wrong: both are the «Mostra la soluzione» button); "finished" when such a serve ended and the
  #           solution, if any, came by itself (after the last try, after a right answer, after «Per me va bene così»), or the open serve has
  #           a try (he answered; a click still resumes it); "opened" when there is an open serve (no try, nothing typed: he only opened it, D-384, «Aperto»); else "todo".
  #           open_serve_id is set whenever the item has an open serve, so a click resumes it. A replaced serve (the topic was revised while it was open,
  #           D-377) is neither open nor ended: it takes no part in the status, so the exercise reads as to do (or done by another serve) and a click serves it
  #           anew from the revision he is shown; its tries still count for the skill.
  #
  #           A skill whose exercises are all «done» while it is not shown yet carries `all_done_it` (D-390), the line that says what is still needed.
  #
  # The list never holds a key to an answer, an error value or the text of an instance: only the item's key (the page asks for that exercise
  # with it), its place and a title, the first sentence of the prompt's stem (the same for every instance).
  class Exercises
    # The reasons of a `solution_shown` event that are the student's own request; the others (after_last_try, after_correct, after_undetermined,
    # after_contest) are the app showing it.
    ASKED_REASONS = %w[requested after_wrong].freeze
    TITLE_MAX = 90
    ELLIPSIS = "…".freeze
    STOPS = %w[. ? !].freeze

    # topic: Course::Catalog::TopicView; view: Course::StudentView (labels and skill states); subject: the topic's Subject; root: the front of
    # the student's addresses ("" for S, "/teacher/preview" in the preview), so the links stay where the student is.
    def self.call(topic:, subject:, student:, view:, root:, now: Time.current) = new(topic, subject, student, view, root, now).call

    # The first sentence of a stem, at most TITLE_MAX characters, lesson markup kept whole (a `$…$` or `[[…]]` is never cut nor ended inside).
    # "" when there is no text.
    def self.title_of(stem)
      text = stem.to_s.squish
      return "" if text.empty?

      inside = inside_flags(text)
      stop = text.each_char.each_with_index.find { |c, i| STOPS.include?(c) && !inside[i] && (i == text.length - 1 || text[i + 1] == " ") }&.last
      sentence = stop ? text[0..stop] : text
      return sentence if sentence.length <= TITLE_MAX

      cut_at_word(sentence, inside)
    end

    # true for every character from the opener to the closer of a `$…$` or a `[[…]]` (both ends included).
    def self.inside_flags(text)
      flags = Array.new(text.length, false)
      i = 0
      while i < text.length
        if text[i] == "\\"
          i += 2
        elsif text[i] == "$"
          j = i + 1
          j += text[j] == "\\" ? 2 : 1 while j < text.length && text[j] != "$"
          if j < text.length
            (i..j).each { |k| flags[k] = true }
            i = j + 1
          else
            i += 1
          end
        elsif text[i, 2] == "[["
          close = text.index("]]", i + 2)
          if close
            (i..close + 1).each { |k| flags[k] = true }
            i = close + 2
          else
            i += 2
          end
        else
          i += 1
        end
      end
      flags
    end

    # At most TITLE_MAX characters with the ellipsis: cut at the last space outside the markup; else before the markup that crosses the limit.
    def self.cut_at_word(sentence, inside)
      limit = TITLE_MAX - ELLIPSIS.length
      space = (1..limit).to_a.reverse.find { |i| sentence[i] == " " && !inside[i] }
      opener = (1...limit).to_a.reverse.find { |i| inside[i] && !inside[i - 1] } if inside[limit]
      cut = space || opener || limit
      sentence[0, cut].sub(/[\s,;:]+\z/, "") + ELLIPSIS
    end

    def initialize(topic, subject, student, view, root, now)
      @topic = topic
      @subject = subject
      @student = student
      @view = view
      @root = root
      @now = now
    end

    def call
      practice = @topic.topic_revision.body["practice"]
      { topic: @topic.key, done: @view.status(@topic) == :done, known: @view.known?(@topic),
        skills: @topic.skills.filter_map { |skill| (pins = practice.find { |p| p["skill"] == skill }) && skill_block(skill, pins["items"]) } }
    end

    private

    def skill_block(skill, pins)
      state = @view.state(skill)
      rows = Loader.for(@student, subject: @subject, skill: skill, seeds: false, now: @now, shown: @view.shown_revisions).serves
      revisions = ItemRevision.where(id: pins.map { |p| p["revision"] }).index_by(&:id)
      facts = Facts.new(rows, drafts_for(rows))
      exercises = pins.each_with_index.map { |pin, i| exercise(pin, i + 1, revisions[pin["revision"]], facts) }
      { key: skill, label_it: @view.label(skill), state: state&.state, state_it: state ? Messages.skill_state_it(state) : Messages.state_it(nil),
        url: "#{@root}/topics/#{@topic.key}/practice/#{skill}", all_done_it: all_done_it(state, exercises), exercises: exercises }
    end

    # D-390: every exercise of the skill is «Fatto» and the skill is not shown yet (the fingerprints that count are fewer than 3, or fewer than 2
    # of them hard to guess): the one line that says what to do, from what the fold says is missing. nil otherwise.
    def all_done_it(state, exercises)
      return nil unless state && exercises.any? && exercises.all? { |e| e[:status] == "done" }

      gap = Messages.missing(state.why) or return nil
      hard = gap[:long].positive? && gap[:long] >= gap[:exercises] # every one still to come must be hard to guess
      I18n.t("practice.all_done.#{hard ? 'long' : 'plain'}", count: gap[:exercises], next: I18n.t("practice.next"))
    end

    def exercise(pin, n, revision, facts)
      mine = facts.of_item(revision.item_id)
      open = facts.open_serve(revision.item_id)
      { item: pin["item"], n: n, title_it: self.class.title_of(JSON.parse(revision.body_json).dig("prompt", "stem_it")),
        status: status(mine, open, facts), open_serve_id: open&.id,
        done: mine.count { |r| r.status.closed_by == :correct }, tried: mine.count { |r| facts.tries(r.id).positive? } }
    end

    def status(mine, open, facts)
      return "unfinished" if open && facts.tries(open.id).zero? && facts.draft?(open.id)
      return "done" if mine.any? { |r| r.status.closed_by == :correct }
      return "contested" if !open && mine.any? { |r| r.status.closed_by == :contested } # D-389: «Per me va bene così», sent to the teacher

      ended = mine.select { |r| (!%i[open replaced].include?(r.status.state) || r.id == open&.id) && (facts.tries(r.id).positive? || r.status.solution_sent) }
      return (ended.any? { |r| facts.asked_solution?(r.id) } ? "finished_solution" : "finished") if ended.any?

      open ? "opened" : "todo"
    end

    def drafts_for(rows) = PracticeDraft.texts_for(rows.map(&:id))

    # The serves of one skill grouped by item, the tries counted by serve and the serves with a draft.
    class Facts
      def initialize(rows, drafts)
        @by_item = rows.group_by(&:item_id)
        @drafts = drafts
        @asked = rows.empty? ? Set.new : asked_serves(rows)
        @tries = rows.empty? ? {} : PracticeAttempt.where(practice_serve_id: rows.map(&:id)).group(:practice_serve_id).count
      end

      def of_item(item_id) = @by_item.fetch(item_id, [])
      def tries(serve_id) = @tries.fetch(serve_id, 0)
      def draft?(serve_id) = @drafts.key?(serve_id)
      def asked_solution?(serve_id) = @asked.include?(serve_id)

      # An item's only possible open serve is its latest one: a newer serve of the same item supersedes it (practice/3).
      def open_serve(item_id)
        latest = of_item(item_id).max_by(&:id)
        latest if latest&.status&.state == :open
      end

      private

      def asked_serves(rows)
        PracticeEvent.where(practice_serve_id: rows.map(&:id), kind: "solution_shown").pluck(:practice_serve_id, :payload_json)
                     .filter_map { |id, json| id if ASKED_REASONS.include?(JSON.parse(json || "{}")["reason"]) }.to_set
      end
    end
  end
end
