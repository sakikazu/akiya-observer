# 物件の地図表示用データを提供する。
class MapsController < ApplicationController
  def index
    listings = SourceListing.includes(:listing_images).order(source_updated_at: :desc)
    @missing_geocodes = listings.where(latitude: nil, longitude: nil).limit(50)
    @missing_count = listings.where(latitude: nil, longitude: nil).count
    @map_listings = listings.where.not(latitude: nil, longitude: nil).map { |listing| map_payload(listing) }
    @map_schools = ElementarySchool.where.not(latitude: nil, longitude: nil).map { |school| school_payload(school) }
  end

  private

  def map_payload(listing)
    image = listing.listing_images.find(&:is_main) || listing.listing_images.first
    {
      id: listing.id,
      title: listing.title,
      price: formatted_price(listing.price),
      layout: listing.layout,
      address: listing.address,
      address_precision: listing.address_precision,
      latitude: listing.latitude&.to_f,
      longitude: listing.longitude&.to_f,
      land_area: listing.land_area,
      building_area: listing.building_area,
      municipality_id: listing.municipality_id,
      url: listing.url,
      source_updated_at: listing.source_updated_at&.to_date&.to_s,
      disappeared_at: listing.disappeared_at&.to_date&.to_s,
      image_url: image_url(image)
    }
  end

  def school_payload(school)
    {
      id: school.id,
      name: school.name,
      address: school.address,
      latitude: school.latitude&.to_f,
      longitude: school.longitude&.to_f,
      memo: school.memo,
      detail_url: school.detail_url,
      municipality_id: school.municipality_id,
      total_students: school.total_students,
      teachers_count: school.teachers_count
    }
  end

  def formatted_price(price)
    return if price.blank?

    view_context.number_to_currency(price, unit: "¥", precision: 0, format: "%u%n")
  end

  def image_url(image)
    return if image.nil?
    return listing_image_path(image) if image.local_path.present?

    image.remote_url
  end
end
