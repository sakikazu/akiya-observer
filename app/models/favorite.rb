# お気に入り物件をユーザーと紐付ける。
class Favorite < ApplicationRecord
  belongs_to :user
  belongs_to :source_listing

  validates :source_listing_id, uniqueness: { scope: :user_id }
end
