module Comments
  # «I miei commenti» of the student (D-349), the list of conversations like a mailbox: one row per comment, the newest
  # activity first (the last message of its thread, D-342), with the tabs Tutti, Risposte nuove (a teacher message not seen
  # yet), In attesa (the student has the last word) and Chiusi, each with its count. Reads only the student's own comments;
  # it writes nothing (opening the list marks nothing seen, opening a conversation does).
  class StudentInbox
    TABS = %w[all new waiting closed].freeze
    Row = Struct.new(:comment, :last, :unread, :state, keyword_init: true) do
      def at = last.at
    end

    attr_reader :tab

    def initialize(student, tab: nil)
      @student = student
      @tab = TABS.include?(tab.to_s) ? tab.to_s : "all"
    end

    def all_rows
      @all_rows ||= Comment.where(student: @student).includes(:events, :subject).to_a
                           .map { |c| Row.new(comment: c, last: c.thread.last, unread: c.unread_reply?, state: c.state) }
                           .sort_by { |r| [ -r.at.to_f, -r.comment.id ] }
    end

    def rows = all_rows.select { |r| member?(r, tab) }

    def counts = TABS.to_h { |t| [ t, all_rows.count { |r| member?(r, t) } ] }

    def member?(row, tab)
      case tab
      when "new" then row.unread
      when "waiting" then %w[sent read].include?(row.state)
      when "closed" then row.state == "closed"
      else true
      end
    end
  end
end
