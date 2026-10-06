class Item < ApplicationRecord
  KEY = /\A[a-z0-9][a-z0-9_-]{0,63}\z/

  belongs_to :subject
  has_many :revisions, class_name: "ItemRevision"

  # Reserve (D-125): the items of a subject that the subject's latest blueprint does not
  # pin. Derived, nothing is stored: pin one and it is in the test again. With no
  # blueprint yet, nothing is a reserve.
  def self.reserve(subject)
    blueprint = BlueprintRevision.where(subject: subject).order(:seq).last
    return none unless blueprint

    pinned = ItemRevision.where(id: blueprint.pinned_item_revision_ids).select(:item_id)
    where(subject: subject).where.not(id: pinned)
  end

  def latest_revision = revisions.max_by(&:seq)
end
