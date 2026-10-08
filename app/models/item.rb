class Item < ApplicationRecord
  KEY = /\A[a-z0-9][a-z0-9_-]{0,63}\z/

  # Diagnosis items feed the entry test; practice items feed the course (Phase 1b). A
  # blueprint never pins a practice item, a topic never pins a diagnosis item (A11).
  DIAGNOSIS_KINDS = %w[diagnosis_item short_answer testlet].freeze
  PRACTICE_KINDS = %w[practice_item].freeze

  belongs_to :subject
  has_many :revisions, class_name: "ItemRevision"

  scope :diagnosis, -> { where(kind: DIAGNOSIS_KINDS) }
  scope :practice, -> { where(kind: PRACTICE_KINDS) }

  def practice? = PRACTICE_KINDS.include?(kind)

  # Reserve (D-125): the items of a subject that the subject's latest blueprint does not
  # pin. Derived, nothing is stored: pin one and it is in the test again. With no
  # blueprint yet, nothing is a reserve.
  def self.reserve(subject)
    blueprint = BlueprintRevision.where(subject: subject).order(:seq).last
    return none unless blueprint

    pinned = ItemRevision.where(id: blueprint.pinned_item_revision_ids).select(:item_id)
    diagnosis.where(subject: subject).where.not(id: pinned)
  end

  def latest_revision = revisions.max_by(&:seq)
end
