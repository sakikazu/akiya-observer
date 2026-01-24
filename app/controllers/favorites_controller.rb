# お気に入りを追加・削除する。
class FavoritesController < ApplicationController
  before_action :authenticate_user!

  def create
    listing = SourceListing.find(params[:source_listing_id])
    favorite = current_user.favorites.find_or_create_by!(source_listing: listing)

    render json: { id: favorite.id, source_listing_id: listing.id }
  end

  def destroy
    favorite = current_user.favorites.find_by!(source_listing_id: params[:source_listing_id])
    favorite.destroy!

    render json: { source_listing_id: params[:source_listing_id].to_i }
  end
end
