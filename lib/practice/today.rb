# frozen_string_literal: true

module Practice
  # Oggi (A8.8), pure: what to do now, with the reason of each suggestion. Reads only plain values:
  #
  #   catalog:    [SubjectView] (Course::Catalog.for), each answering subject (key, position) and topics
  #               [TopicView] (key, skills, after) in course order
  #   states:     {skill => SkillState}
  #   graph_order: {skill => position} (Practice::GraphOrder)
  #   last_topic: key of the topic of the student's latest serve or lesson_opened, or nil
  module Today
    V6 = Rules::V6

    Suggestion = Data.define(:topic_key, :reason, :skill)

    DONE = %w[demonstrated consolidated].freeze
    # The states the tag on a topic marks (`banco next` lists the same skills, D-333), to_recover first.
    RECOVER = %w[to_recover to_review].freeze

    module_function

    # limit: how many suggestions to keep (Oggi's SUGGESTIONS_MAX); nil keeps the whole ranked list, whose first per subject is
    # the topic Oggi proposes for that subject (D-333, `banco next`).
    def call(catalog:, states:, graph_order:, last_topic:, limit: V6::SUGGESTIONS_MAX)
      views = catalog.flat_map { |sv| sv.topics.each_with_index.map { |t, i| [ sv, t, i ] } }
      visible = views.to_h { |sv, t, i| [ t.key, [ sv, t, i ] ] }
      resume = last_topic if last_topic && visible.key?(last_topic) && !done?(visible.fetch(last_topic)[1], states)
      open_views = views.reject { |_, t, _| t.key == resume || done?(t, states) }
      taken = Set.new
      suggestions = []
      %w[to_recover to_learn to_review].each do |reason|
        rows = open_views.filter_map do |sv, t, i|
          next if taken.include?(t.key)

          skills = t.skills.select { |s| states[s]&.state == reason }
          next if skills.empty?

          skill = skills.min_by { |s| [ graph_order.fetch(s, Float::INFINITY), s ] }
          [ sv, t, i, skill ]
        end
        add(suggestions, taken, rows, reason.to_sym, graph_order, by_graph: reason != "to_review")
      end
      rest = open_views.reject { |_, t, _| taken.include?(t.key) }.map { |sv, t, i| [ sv, t, i, nil ] }
      add(suggestions, taken, rest, :course_next, graph_order, by_graph: false)
      { resume: resume, suggestions: limit ? suggestions.first(limit) : suggestions }
    end

    def add(suggestions, taken, rows, reason, graph_order, by_graph:)
      per_subject = rows.group_by { |sv, *| sv.subject.position }.sort.map do |_, list|
        by_graph ? list.sort_by { |_, _, i, skill| [ graph_order.fetch(skill, Float::INFINITY), i ] } : list.sort_by { |_, _, i, _| i }
      end
      interleave(per_subject).each do |_, t, _, skill|
        taken << t.key
        suggestions << Suggestion.new(topic_key: t.key, reason: reason, skill: skill)
      end
    end

    # Round robin over the subjects (already in Subject.position order).
    def interleave(lists)
      out = []
      until lists.all?(&:empty?)
        lists.each { |l| out << l.shift unless l.empty? }
      end
      out
    end

    # done: every skill of the topic is demonstrated or consolidated.
    def done?(topic, states)
      topic.skills.all? { |s| DONE.include?(states[s]&.state) }
    end

    # :done, :in_progress (any try or a lesson_opened) or :todo. started: the topic has a try or a lesson_opened.
    def status(topic, states, started:)
      return :done if done?(topic, states)

      started ? :in_progress : :todo
    end

    # The tag on a topic (the student reads «Dal test: da ripassare» for a to_recover skill, «Da ripassare» for a to_review one, D-348): a skill is
    # to_recover or to_review.
    def recover_tag?(topic, states) = !recover_kind(topic, states).nil?

    # "to_recover" when a skill of the topic is, else "to_review" when one is, else nil: which tag, and which line explains it.
    def recover_kind(topic, states)
      kinds = topic.skills.map { |s| states[s]&.state }
      RECOVER.find { |kind| kinds.include?(kind) }
    end

    # "Prima conviene fare": the first `after` topic that is visible and not done (A8.8). visible: {key => topic}.
    def before(topic, visible, states)
      key = topic.after.find { |k| visible.key?(k) && !done?(visible.fetch(k), states) }
      key && visible.fetch(key)
    end
  end
end
