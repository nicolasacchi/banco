module Changelog
  # What «Novità» shows (D-375): the three sources, read from git and from the ledger, never from a model.
  #
  #   Changelog::Feed.student(student, view)    # the student's page: entries for him, updates of the topics he sees, «Le tue segnalazioni»
  #   Changelog::Feed.teacher(since: date)      # the teacher's page and the API: every entry, every update with its reason and revision ids
  #
  # `since` is a Date (the entries and updates of that day and later) or nil.
  class Feed
    # +updates+: [Update] newest first; +followups+: [Followup] (the student's own comments, his page alone).
    attr_reader :entries, :updates, :followups

    # followups: false leaves «Le tue segnalazioni» out (the API never carries a student's comment).
    def self.student(student, view, since: nil, followups: true)
      updates = ContentUpdates.for_student(view)
      new(entries: Entries.for(:student), updates: updates, followups: followups ? Followups.for(student, view, updates) : [], since: since)
    end

    def self.teacher(since: nil)
      new(entries: Entries.for(:teacher), updates: ContentUpdates.all, followups: [], since: since)
    end

    def initialize(entries:, updates:, followups:, since: nil)
      @entries = Entries.since(entries, since)
      @updates = since ? updates.select { |u| u.date >= since } : updates
      @followups = since ? followups.select { |f| f.date >= since } : followups
    end

    # The updates the student reads: one per topic and day, grouped by day, newest day first.
    def days = ContentUpdates.by_day(updates)

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
