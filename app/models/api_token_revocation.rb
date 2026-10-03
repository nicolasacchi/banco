class ApiTokenRevocation < ApplicationRecord
  belongs_to :api_token
end
