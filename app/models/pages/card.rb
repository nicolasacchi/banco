# The card that embeds (or will embed) a page: all the author of the page may read (SPEC B8). The text of the card, its
# title, the caption of the page block. From the latest stored revision of a lesson of the subject that names the page.
module Pages
  module Card
    module_function

    def for(key, subject)
      Lesson.where(subject: subject).includes(:revisions).order(:key).each do |lesson|
        latest = lesson.latest_revision or next
        next unless latest.lesson2?

        latest.body["cards"].each do |card|
          block = card["blocks"].find { |b| b["type"] == "page" && b["page"] == key } or next
          return { lesson: lesson.key, lesson_revision_id: latest.id, card: card["n"], title_it: card["title_it"], role: card["role"], caption_it: block["caption_it"],
                   text_it: card["blocks"].filter_map { |b| b["text_it"] if %w[text callout].include?(b["type"]) } }
        end
      end
      nil
    end
  end
end
