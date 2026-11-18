# «Ti è piaciuto?» (D-365): the student's box (stars and a comment) and the teacher's «Valutazione» line.
module RatingsHelper
  # The box is on the practice page, the end of a lesson and nowhere else; never in the teacher's preview (it writes none) and never in the
  # entry test (a sitting). A trial student has it, his rows are marked.
  def rating_box? = !preview? && respond_to?(:acting_student) && acting_student.kind == "student"

  # What rating_controller.js says: the star labels, the counter, the states of the box. The question and the buttons are in the markup.
  def rating_labels
    { star_one: t("rating.star.one"), star_other: t("rating.star.other"), chars: t("rating.chars"),
      sending: t("rating.sending"), error: t("rating.error"), invalid: t("rating.invalid"), empty: t("rating.empty"), thanks: t("rating.thanks"),
      you_sent: t("rating.you_sent") }
  end

  # The student's latest rating of this target as the box shows it ({} when there is none).
  def rating_current(kind, key)
    rating = Rating.latest_for(acting_student, kind, key)
    rating ? { stars: rating.stars, text_it: rating.text_it } : {}
  end

  # «Valutazione: 4,2 ★ (5)» for the teacher's pages, linking to the list of that target; nil when no official star counts yet.
  # `summary`: a Rating::Summary; `filters`: the query of the teacher's list the line links to.
  def rating_line(summary, **filters)
    return nil unless summary

    link_to(t("teacher.ratings.line", average: summary.average_it, n: summary.count), teacher_ratings_path(filters), class: "rating-line", "data-rating-line": "")
  end

  # The summaries of every item and of every lesson, read once per request (the cards of a page ask one by one).
  def rating_summaries = @_rating_summaries ||= Rating.summaries
end
