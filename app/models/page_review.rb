# The review of a page revision by an independent session (banco.page_review/1, SPEC B8).
class PageReview < ApplicationRecord
  include ReadTimeIndependence

  belongs_to :page_revision
  belongs_to :agent_session

  def reviewed_thing = page_revision.page

  def checklist = JSON.parse(checklist_json)
  def findings = JSON.parse(findings_json)
end
