class SourceListing < ApplicationRecord
  belongs_to :source_site
  belongs_to :municipality, optional: true

  has_many :favorites, dependent: :destroy
  has_many :listing_images, dependent: :destroy
end
