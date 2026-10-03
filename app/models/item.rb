class Item < ApplicationRecord
  KEY = /\A[a-z0-9][a-z0-9_-]{0,63}\z/

  belongs_to :subject
  has_many :revisions, class_name: "ItemRevision"

  def latest_revision = revisions.max_by(&:seq)
end
