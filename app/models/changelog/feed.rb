module Changelog
  # What «Novità» shows (D-375): the three sources, read from git and from the ledger, never from a model.
  #
  #   Changelog::Feed.student(student, view)                  # the student's data: entries for him, updates of the topics he sees, his comments' follow-ups
  #   Changelog::Feed.student(student, view, recent: true)    # the student's page (D-378): only the last 14 days of topics revised, his comments grouped by topic
  #   Changelog::Feed.teacher(since: date)                    # the teacher's page and the API: every entry, every update with its reason and revision ids
  #
  # `since` is a Date (the entries and updates of that day and later) or nil.
  class Feed
    # The newest entries the page shows in full, and the ones that are new to the student; the rest wait in one closed group (D-378).
    FEATURED_ENTRIES = 3

    # +updates+: [Update] newest first; +followups+: [Followup::Group] one per topic (the student's own comments, his page alone).
    attr_reader :entries, :updates, :followups

    # followups: false leaves «Le tue segnalazioni» out (the API never carries a student's comment).
    # recent: true keeps the topics revised in the last ContentUpdates::RECENT_DAYS days (his follow-ups still read every revision after a comment).
    def self.student(student, view, since: nil, followups: true, recent: false)
      all = ContentUpdates.for_student(view)
      updates = recent ? ContentUpdates.recent(all) : all
      groups = followups ? Followups.group(Followups.for(student, view, all)) : []
      new(entries: Entries.for(:student), updates: updates, followups: groups, since: since, view: view)
    end

    def self.teacher(since: nil)
      new(entries: Entries.for(:teacher), updates: ContentUpdates.all, followups: [], since: since)
    end

    def initialize(entries:, updates:, followups:, since: nil, view: nil)
      @entries = Entries.since(entries, since)
      @updates = since ? updates.select { |u| u.date >= since } : updates
      @followups = since ? followups.select { |f| f.date >= since } : followups
      @view = view
    end

    # The updates the student reads: one per topic and day, grouped by day, newest day first.
    def days = ContentUpdates.by_day(updates)

    # The same days for the page: [[Date, in_play, others]]. in_play are the topics he has started or that are next for him, listed in full; others
    # are the rest of that day, folded into one line (D-378).
    def day_groups
      days.map do |date, list|
        in_play, others = list.partition { |update| @view.in_play?(@view.find_topic(update.topic).last) }
        [ date, in_play, others ]
      end
    end

    # The entries shown in full (the newest ones, and every one that is new after +since+) and the older rest, which the page folds.
    def featured_entries(since)
      entries.each_with_index.partition { |entry, index| index < FEATURED_ENTRIES || (since && entry.at > since) }.map { |pairs| pairs.map(&:first) }
    end

    # The moments of everything on the page, to compare with the student's last visit.
    def moments = entries.map(&:at) + updates.map(&:at) + followups.map(&:revised_at)

    # How many things came after +since+ (a moment): the entries by their day, the updates and the replies by their time.
    def new_count(since)
      entries.count { |e| e.at > since } + days.sum { |_, list| list.count { |u| u.at > since } } + followups.count { |f| f.revised_at > since }
    end

    def newer_than?(since) = moments.any? { |at| at > since }

    def empty? = entries.empty? && updates.empty? && followups.empty?
  end
end
