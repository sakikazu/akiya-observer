class SourceListing < ApplicationRecord
  belongs_to :source_site
  has_many :listing_images, dependent: :destroy
end
