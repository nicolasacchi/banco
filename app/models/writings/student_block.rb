module Writings
  # «Scrivi tu» (D-407): what the topic page draws for the writing tasks of the topic revision this student is shown, and where each stands for him: not
  # written yet (:new), sent and waiting for the teacher (:sent) or corrected (:corrected). Read-only. A writing task is not an exercise: nothing here is a
  # try, a skill state or part of the topic's completion.
  #
  #   Writings::StudentBlock.new(student, topic_view).tasks   # => [Task]
  class StudentBlock
    # prompt: the task as he reads it (Writings::Prompt: the task text, the answer format, the word range, each in the language he studies when the item has
    # the pair and with its Italian when that is a translation to offer). versions: his texts of this item (any revision of it), newest first.
    Task = Data.define(:revision, :item_key, :prompt, :versions) do
      def latest = versions.first
      def state = latest.nil? ? :new : (latest.correction ? :corrected : :sent)
    end
    Version = Data.define(:submission, :correction)

    def initialize(student, topic)
      @student = student
      @topic = topic
    end

    def any? = tasks.any?

    # Whether the Italian of a task's text is a translation to offer (so the page offers the «Traduzione» button).
    def translations? = tasks.any? { |t| t.prompt.translations? }

    # The tasks, in the order of the topic file.
    def tasks
      @tasks ||= begin
        pins = @topic.topic_revision.writing_pins
        revisions = ItemRevision.where(id: pins.map { |pin| pin["revision"] }).includes(:item).index_by(&:id)
        pins.filter_map { |pin| revisions[pin["revision"]] }.map { |revision| task(revision) }
      end
    end

    # Every correction the student has not opened yet, among the texts of this topic's tasks (the topic page records them as seen).
    def corrected
      tasks.filter_map { |t| t.latest&.correction }
    end

    private

    def task(revision)
      body = JSON.parse(revision.body_json)
      submissions = @student ? WritingSubmission.of_student(@student).of_item(revision.item).newest_first.to_a : []
      corrections = Writings::Corrections.for(submissions)
      Task.new(revision: revision, item_key: revision.item.key, prompt: Writings::Prompt.of(body, @topic.lang),
               versions: submissions.map { |s| Version.new(s, corrections[s.id]) })
    end
  end
end
