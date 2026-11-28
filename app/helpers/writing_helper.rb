# «Scrivi tu» (D-407): the texts the writing box's script says, in the language of the student's interface.
module WritingHelper
  # The labels writing_controller.js reads (a count carries its %{count} placeholder: the script fills it in).
  def writing_labels
    { one: t("writing.words_one"), other: t("writing.words_other", count: "%{count}"), chars: t("writing.chars", n: "%{n}", max: WritingSubmission::TEXT_MAX),
      sending: t("writing.sending"), sent: t("writing.sent"), empty: t("writing.empty"), too_long: t("writing.too_long", max: WritingSubmission::TEXT_MAX),
      pending: t("writing.pending"), error: t("writing.error"), invalid: t("writing.invalid") }
  end
end
