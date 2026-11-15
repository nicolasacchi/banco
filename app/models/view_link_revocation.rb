# The end of a view link before its expiry (D-332). One row per link; api_token is the token that revoked it over the API.
# Append-only: a revoked link is never active again.
class ViewLinkRevocation < ApplicationRecord
  belongs_to :view_link
  belongs_to :api_token, optional: true
end
