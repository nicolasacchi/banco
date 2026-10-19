# One revision of a free page: the manifest (banco.page/1) and the files of the bundle, named by content (SPEC B2, B9).
class PageRevision < ApplicationRecord
  belongs_to :page
  belongs_to :base_revision, class_name: "PageRevision", optional: true
  belongs_to :author_session, class_name: "AgentSession", optional: true
  has_many :files, class_name: "PageFile"
  has_many :validations, class_name: "PageValidation"
  has_many :reviews, class_name: "PageReview"

  # The reviews that count (D-316): the session ran on another TRUE model than every author of the page.
  def counting_reviews = Providers.counting(reviews.includes(agent_session: :corrections), page)

  def manifest = JSON.parse(manifest_json)
  def warnings = JSON.parse(warnings_json)

  # The latest passed validation, or nil: the kit it ran with is the kit the lesson embeds (B4, B6).
  def passed_validation = validations.select { |v| v.status == "passed" }.max_by(&:id)

  def latest_validation = validations.max_by(&:id)

  # The latest validation that reached a verdict (error rows are attempts).
  def verdict = validations.select { |v| %w[passed failed].include?(v.status) }.max_by(&:id)
end
