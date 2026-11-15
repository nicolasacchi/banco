# One row per time a view link's URL was opened (D-332): the audit of who may have looked. No address: the peer is the
# edge proxy. Append-only.
class ViewLinkRedemption < ApplicationRecord
  belongs_to :view_link
end
