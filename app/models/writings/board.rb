module Writings
  # «Testi da correggere» (D-407): the texts one student wrote himself and what the teacher answered, as the teacher's page, the Cruscotto and the API read
  # them. Pending first (the oldest waits longest, so it comes first), then the corrected ones, newest first. Read-only; the form of the page posts the
  # decision `correct_writing`. Only real students' texts (official or trial, never the preview's).
  #
  #   Writings::Board.new(student: Student.official).entries
  class Board
    # task_it: what the student was asked, as the teacher reads it (both languages of a bilingual task). correction: the latest of the decisions or nil.
    Entry = Data.define(:submission, :subject, :topic_key, :topic_title, :item_key, :task_it, :words_min, :words_max, :notes_it, :correction) do
      def pending? = correction.nil?
    end

    attr_reader :student

    def initialize(student: Student.official)
      @student = student
    end

    def entries
      @entries ||= begin
        rows = student ? WritingSubmission.of_student(student).includes(:student, item_revision: :item, topic_revision: { lesson: :subject }).to_a : []
        corrections = Writings::Corrections.for(rows)
        built = rows.map { |s| build(s, corrections[s.id]) }
        pending, done = built.partition(&:pending?)
        pending.sort_by { |e| e.submission.id } + done.sort_by { |e| -e.submission.id }
      end
    end

    def pending = entries.select(&:pending?)
    def corrected = entries.reject(&:pending?)
    def count = pending.size

    # {Subject => pending texts in it}, for the Cruscotto's line per subject.
    def pending_by_subject = pending.map(&:subject).tally

    # One text by id for the API, with the same fields (nil when there is none, or it is the preview's).
    def self.find(id)
      submission = WritingSubmission.includes(:student, item_revision: :item, topic_revision: { lesson: :subject }).find_by(id: id)
      return nil unless submission&.student&.kind == "student"

      new(student: submission.student).build(submission, Writings::Corrections.for([ submission ])[submission.id])
    end

    # One text as an Entry.
    def build(submission, correction)
      body = JSON.parse(submission.item_revision.body_json)
      subject = submission.subject
      Entry.new(submission: submission, subject: subject, topic_key: submission.topic_key, topic_title: title(subject, submission.topic_key), item_key: submission.item_key,
                task_it: Items::Text.both_of(body["prompt"], "stem"), words_min: body["words_min"], words_max: body["words_max"], notes_it: body["teacher_notes_it"], correction: correction)
    end

    private

    def title(subject, key)
      @titles ||= {}
      @titles[[ subject.id, key ]] ||= Approval::TopicGate.map_entry(subject, key)&.dig("title_it") || key
    end
  end
end
