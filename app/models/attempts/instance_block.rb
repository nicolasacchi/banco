module Attempts
  # The instance of a try as the teacher reads it (D-346): Teacher::InstanceView's stem, key in words and errors, the key as stored, the forms
  # accepted, the item's error catalogue, the codes the grader matched with their texts, and the answer in the words of the shown display.
  module InstanceBlock
    module_function

    # shown: Attempts::Shown of the serve; codes: the error codes of the latest grading.
    def call(instance, shown, raw, codes)
      revision = instance.item_revision
      view = Teacher::InstanceView.new(instance, shown.body, 1)
      catalogue = Teacher::ItemCard.catalogue_of(shown.body)
      { id: instance.id, revision_id: revision.id, item: revision.item.key, fingerprint: instance.fingerprint, stem: view.stem, key: shown.answer, key_words: view.key,
        accept: Items::Part.accepted(shown.body, instance.accept_json.present? ? JSON.parse(instance.accept_json) : []), answer_words: shown.words(raw),
        errors: view.errors, error_catalogue: catalogue,
        matched_errors: codes.map { |code| { code: code, message_it: catalogue.find { |e| e["code"] == code }&.dig("message_it") }.compact } }
    end
  end
end
