# A file of a page revision: the row names the bytes (storage/pages/<sha256>, written once by Pages::Store).
class PageFile < ApplicationRecord
  belongs_to :page_revision
end
