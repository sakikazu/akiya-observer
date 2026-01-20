namespace :geocode do
  desc "Geocode SourceListing addresses (default: limit=200)"
  task source_listings: :environment do
    limit = ENV.fetch("LIMIT", "200").to_i
    throttle = ENV.fetch("THROTTLE", "1.0").to_f
    client = Geocoding::NominatimClient.new
    Geocoding::SourceListingGeocoder.new(client: client, throttle_seconds: throttle).call(limit: limit)
  end
end
