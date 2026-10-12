# A free page (SPEC B2): a content unit with revisions, key SUBJECT.slug (math.balance-3d). Append-only.
class Page < ApplicationRecord
  KEY = /\A([a-z_]+)\.([a-z0-9]+(?:-[a-z0-9]+)*)\z/

  belongs_to :subject
  has_many :revisions, class_name: "PageRevision"

  def latest_revision = revisions.max_by(&:seq)
end
