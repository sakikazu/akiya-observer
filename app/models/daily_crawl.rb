class DailyCrawl < ApplicationRecord
  belongs_to :source_site

  validates :crawled_on, presence: true
  validates :status, presence: true
  validates :listing_count, numericality: { greater_than_or_equal_to: 0 }
  validates :crawled_on, uniqueness: { scope: :source_site_id }
end
