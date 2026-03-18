# 物件の地図表示用データを提供する。
require "set"
class MapsController < ApplicationController
  def index
    listings = SourceListing.includes(:listing_images).order(source_updated_at: :desc)
    favorite_ids = favorite_listing_ids
    @favorite_listings = favorite_listings
    @map_listings = listings.where.not(latitude: nil, longitude: nil).map { |listing| map_payload(listing, favorite_ids) }
    @map_schools = ElementarySchool.where.not(latitude: nil, longitude: nil).map { |school| school_payload(school) }
    @map_missing_municipalities = missing_municipality_payloads(listings, favorite_ids)
    @municipality_options = municipality_options(listings)
  end

  private

  MISSING_LISTINGS_SAMPLE_LIMIT = 20

  def map_payload(listing, favorite_ids = nil)
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
      first_seen_at: listing.first_seen_at&.to_date&.to_s,
      favorite: favorite_ids ? favorite_ids.include?(listing.id) : false,
      disappeared_at: listing.disappeared_at&.to_date&.to_s,
      image_url: image_url(image),
      highlight_text: listing.highlight_text
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

  # 座標未取得の市区町村を代表点付きでまとめる。
  def missing_municipality_payloads(listings, favorite_ids = nil)
    missing_scope = listings.where(latitude: nil, longitude: nil).where.not(municipality_id: nil)
    missing_counts = missing_scope.group(:municipality_id).count
    return [] if missing_counts.empty?

    municipality_ids = missing_counts.keys

    names, representative_coords = municipality_metadata(municipality_ids)
    listing_avgs = average_coords(listings.where(municipality_id: municipality_ids).where.not(latitude: nil, longitude: nil))
    school_avgs = average_coords(ElementarySchool.where(municipality_id: municipality_ids).where.not(latitude: nil, longitude: nil))

    samples_by_municipality = Hash.new { |hash, key| hash[key] = [] }
    missing_scope.order(source_updated_at: :desc).find_each do |listing|
      samples = samples_by_municipality[listing.municipality_id]
      next if samples.size >= MISSING_LISTINGS_SAMPLE_LIMIT

      samples << map_payload(listing, favorite_ids)
    end

    municipality_ids.map do |municipality_id|
      representative = representative_coords[municipality_id] || {}
      latitude = representative[:latitude] || listing_avgs[:latitudes][municipality_id] || school_avgs[:latitudes][municipality_id]
      longitude = representative[:longitude] || listing_avgs[:longitudes][municipality_id] || school_avgs[:longitudes][municipality_id]
      next if latitude.nil? || longitude.nil?

      samples = samples_by_municipality[municipality_id]
      {
        municipality_id: municipality_id,
        name: names[municipality_id] || "市区町村不明",
        latitude: latitude.to_f,
        longitude: longitude.to_f,
        representative_set: representative[:latitude].present? && representative[:longitude].present?,
        count: missing_counts[municipality_id],
        remaining_count: missing_counts[municipality_id] - samples.size,
        listings: samples
      }
    end.compact
  end

  # 市区町村名と代表点を取得する。
  def municipality_metadata(municipality_ids)
    names = {}
    representative_coords = {}
    Municipality.where(id: municipality_ids)
      .pluck(:id, :name, :representative_latitude, :representative_longitude).each do |(id, name, latitude, longitude)|
        names[id] = name
        representative_coords[id] = { latitude: latitude, longitude: longitude }
      end
    [names, representative_coords]
  end

  # 市区町村ごとの緯度経度平均を返す。
  def average_coords(scope)
    {
      latitudes: scope.group(:municipality_id).average(:latitude),
      longitudes: scope.group(:municipality_id).average(:longitude)
    }
  end

  def formatted_price(price)
    return if price.blank?

    view_context.number_to_currency(price, unit: "¥", precision: 0, format: "%u%n")
  end

  def favorite_listing_ids
    return Set.new unless user_signed_in?

    current_user.favorites.pluck(:source_listing_id).to_set
  end

  def favorite_listings
    return [] unless user_signed_in?

    current_user.favorite_listings.includes(:listing_images)
      .order(source_updated_at: :desc)
  end

  def image_url(image)
    return if image.nil?
    return listing_image_path(image) if image.local_path.present?

    image.remote_url
  end

  # 地図サイドバーの市区町村セレクト用の一覧を作る。
  def municipality_options(listings)
    counts = listings.where.not(municipality_id: nil).group(:municipality_id).count
    return [] if counts.empty?

    Municipality.joins(:prefecture)
      .where(id: counts.keys)
      .order("prefectures.code ASC", "municipalities.name ASC")
      .pluck("municipalities.id", "prefectures.name", "municipalities.name")
      .map do |(id, prefecture_name, municipality_name)|
        {
          id: id,
          name: "#{prefecture_name} #{municipality_name}",
          count: counts[id]
        }
      end
  end
end
