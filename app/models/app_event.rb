class AppEvent < ApplicationRecord
  belongs_to :student, optional: true
end
