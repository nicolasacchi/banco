module Course
  # Educazione civica (D-345): not a subject, a reading of topics that other subjects already teach, grouped by the three
  # nuclei of the 2024 Linee guida (config/banco/civics.yml). Built only from what Course::StudentView shows this student
  # (official, trial or the teacher's preview with its view): a key she cannot see is skipped, and the status of a topic is
  # the one the subject page shows. No query of its own, no count in the progress of a subject, never read by Oggi.
  #
  #   civics = Course::Civics.new(course_view)
  #   civics.any?            # at least one topic is visible: the card and the page exist
  #   civics.topic_count     # => N argomenti
  #   civics.nuclei          # => [Nucleus(key:, title_it:, intro_it:, entries: [Entry])] with at least one entry each
  class Civics
    CONFIG = Rails.root.join("config/banco/civics.yml")

    Nucleus = Data.define(:key, :title_it, :intro_it, :entries)
    # subject_view: Catalog::SubjectView; topic: Catalog::TopicView; status: :todo, :in_progress or :done.
    Entry = Data.define(:subject_view, :topic, :status) do
      def extra? = topic.extra?
    end

    # The nuclei as written in git: [{ "key", "title_it", "intro_it", "topics" => [lesson keys] }].
    def self.config = @config ||= YAML.safe_load_file(CONFIG, aliases: false).fetch("nuclei").freeze

    def initialize(view)
      @view = view
    end

    def nuclei
      @nuclei ||= self.class.config.filter_map do |nucleus|
        entries = nucleus.fetch("topics").filter_map do |key|
          found = @view.find_topic(key) or next
          Entry.new(subject_view: found[0], topic: found[1], status: @view.status(found[1]))
        end
        next if entries.empty?

        Nucleus.new(key: nucleus.fetch("key"), title_it: nucleus.fetch("title_it"), intro_it: nucleus.fetch("intro_it"), entries: entries)
      end
    end

    def topic_count = nuclei.sum { |nucleus| nucleus.entries.size }

    def any? = topic_count.positive?
  end
end
