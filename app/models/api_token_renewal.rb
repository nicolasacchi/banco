# A token's later expiry, recorded when a public token is used close enough to its end (D-330). Append-only: the
# effective expiry of a token is the latest expires_at of the token and its renewals (ApiToken#effective_expires_at).
class ApiTokenRenewal < ApplicationRecord
  belongs_to :api_token
end
