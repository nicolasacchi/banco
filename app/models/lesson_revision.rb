class LessonRevision < ApplicationRecord
  belongs_to :lesson
  belongs_to :base_revision, class_name: "LessonRevision", optional: true
  belongs_to :author_session, class_name: "AgentSession", optional: true
  has_many :reviews, class_name: "LessonReview"

  def body = JSON.parse(body_json)
  def warnings = JSON.parse(warnings_json)

  def lesson2? = body["schema"] == "banco.lesson/2"

  # The exercise n of Prova tu, in either format (banco.lesson/1: body.exercises; banco.lesson/2: the exercises of the try block).
  def exercise(n)
    list = lesson2? ? body["cards"].flat_map { |c| c["blocks"] }.select { |b| b["type"] == "try" }.flat_map { |b| b["exercises"] } : Array(body["exercises"])
    list.find { |e| e["n"] == n }
  end
end
