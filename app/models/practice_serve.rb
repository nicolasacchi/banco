# One instance shown to one student in practice (A7, A8.3). Closure is derived from tries.
class PracticeServe < ApplicationRecord
  REASONS = %w[next prova_questo after_solution reseen].freeze

  belongs_to :student
  belongs_to :topic_revision
  belongs_to :item_instance
  belongs_to :parent_serve, class_name: "PracticeServe", optional: true
  has_many :attempts, class_name: "PracticeAttempt"
  has_many :events, class_name: "PracticeEvent"
end
