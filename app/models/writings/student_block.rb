module Writings
  # «Scrivi tu» (D-407): what the topic page draws for the writing tasks of the topic revision this student is shown, and where each stands for him: not
  # written yet (:new), sent and waiting for the teacher (:sent) or corrected (:corrected). Read-only. A writing task is not an exercise: nothing here is a
  # try, a skill state or part of the topic's completion.
  #
  #   Writings::StudentBlock.new(student, topic_view).tasks   # => [Task]
  class StudentBlock
    # stem: the task as he reads it (the language he studies when the item has the pair, else Italian), stem_tr its Italian when it is a translation to offer.
    # versions: his texts of this item (any revision of it), newest first.
    Task = Data.define(:revision, :item_key, :stem, :stem_tr, :lang, :words_min, :words_max, :versions) do
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
    def translations? = tasks.any?(&:stem_tr)

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
      prompt = body["prompt"] || {}
      lang = @topic.lang
      target = lang && prompt["stem_#{lang}"].presence
      stem = target || prompt["stem_it"].to_s
      submissions = @student ? WritingSubmission.of_student(@student).of_item(revision.item).newest_first.to_a : []
      corrections = Writings::Corrections.for(submissions)
      Task.new(revision: revision, item_key: revision.item.key, stem: stem, stem_tr: (prompt["stem_it"].presence if target), lang: (lang if target),
               words_min: body["words_min"], words_max: body["words_max"],
               versions: submissions.map { |s| Version.new(s, corrections[s.id]) })
    end
  end
end
