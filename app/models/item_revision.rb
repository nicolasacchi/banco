class ItemRevision < ApplicationRecord
  belongs_to :item
  belongs_to :author_session, class_name: "AgentSession", optional: true
  has_many :validations, class_name: "ItemValidation"
  has_many :instances, class_name: "ItemInstance"
  has_many :findings, class_name: "ReviewFinding"
  has_many :reviews, class_name: "ItemReview"
  has_many :blind_solves, class_name: "BlindSolve"

  # item.json is body_json; the other files (generator.mjs, verify.mjs, assets/*)
  # are files_json {name => text}.
  def other_files = files_json.present? ? JSON.parse(files_json) : {}

  # Every file of the revision: {"item.json" => text, "generator.mjs" => text, ...}.
  def files = { "item.json" => body_json }.merge(other_files)

  # {file name => agent session id}: who wrote each file as it stands (A-04).
  def file_sessions = file_sessions_json.present? ? JSON.parse(file_sessions_json) : {}

  def latest_validation = validations.max_by(&:seq)

  # passed, failed, error, or validating while no verdict row exists.
  def status = latest_validation&.status || "validating"
end
