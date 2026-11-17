require_relative "student_course_world"

# Two written-answer (normalized_text) practice items on top of StudentCourseWorld (D-339): a sentence with a `___` blank, answered with the words for the
# blank or with the whole sentence, and a single word with no frame. Pinned alone on a new approved topic revision, so a serve of either is asked
# for by its key. Every text is invented.
module PracticeTextWorld
  include StudentCourseWorld

  SENTENCE = "text-sentence".freeze
  WORD = "text-word".freeze
  SENTENCE_STEM = "Negativa: My parents ___ meat.".freeze
  SLIP_MESSAGE = "Con parents si usa don't.".freeze

  def build_text_world
    build_student_world
    @sentence = make_text_item(SENTENCE, stem: SENTENCE_STEM, answer: "don't eat", hints: [ "Pensa al plurale." ],
                                         errors: [ { code: "does_eat", value: "doesn't eat", message_it: SLIP_MESSAGE } ])
    @word = make_text_item(WORD, stem: "Scrivi la parola: ___", answer: "neighbourhood")
    @text_topic = make_topic(@lesson_revision, { SKILL => [ @sentence, @word ] }, course: @course)
    approve_topic!(@text_topic)
  end

  # A practice item of the component normalized_text with several instances that show the same stem and differ only in their fingerprint.
  def make_text_item(key, stem:, answer:, hints: [], errors: [], instances: 6)
    item = Item.create!(subject: @subject, key: key, kind: "practice_item")
    body = { schema: "banco.item/1", schema_version: 1, kind: "practice_item", subject: @subject.key, skill: SKILL, component: "normalized_text", level: 1,
             expected_seconds: 60, hints_it: hints, error_catalogue: errors.map { |e| { code: e[:code], message_it: e[:message_it] } } }
    revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemValidation.create!(item_revision: revision, seq: 1, status: "passed", codes_json: "[]")
    instances.times do |i|
      ItemInstance.create!(item_revision: revision, seed: i + 1, display_json: JSON.generate(stem_it: stem), answer_json: JSON.generate(answer),
                           errors_json: JSON.generate(errors.map { |e| { code: e[:code], value: e[:value] } }), hints_json: JSON.generate(hints),
                           solution_json: JSON.generate(steps: [ { text_it: "Passo." } ], final: answer), fingerprint: Digest::SHA256.hexdigest("#{key}-#{i}"))
    end
    revision
  end
end
