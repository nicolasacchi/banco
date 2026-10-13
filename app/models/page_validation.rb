# One validation of a page revision in the server's Chrome (SPEC B7): append-only, with the kit it ran with.
class PageValidation < ApplicationRecord
  belongs_to :page_revision

  def result = JSON.parse(result_json)
  def shots = JSON.parse(shots_json)
  def errors_list = Array(result["errors"])
  def passed? = status == "passed"
end
