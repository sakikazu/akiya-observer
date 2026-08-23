require "logger"

module Geocoding
  # 住所未ジオコーディングの物件をまとめて座標化する。
  class SourceListingGeocoder
    DEFAULT_THROTTLE_SECONDS = 1.0
    DEFAULT_LIMIT = 200

    def initialize(client: NominatimClient.new, throttle_seconds: DEFAULT_THROTTLE_SECONDS, logger: nil)
      @client = client
      @throttle_seconds = throttle_seconds
      @logger = logger || Logger.new($stdout)
    end

    # 新着に近い物件を優先して座標化する。
    def call(limit: DEFAULT_LIMIT, scope: SourceListing.all)
      scope = scope.where(latitude: nil, longitude: nil).where.not(address: [ nil, "" ])
      total = scope.count
      log("Geocoding up to #{limit} listings (#{total} pending)")

      scope.order(source_updated_at: :desc).limit(limit).find_each do |listing|
        coords = @client.geocode(listing.address)
        sleep(@throttle_seconds) if @throttle_seconds.positive?

        if coords
          listing.update!(coords)
          log("geocoded #{listing.external_id} -> #{coords[:latitude]}, #{coords[:longitude]}")
        else
          log("geocode failed for #{listing.external_id}")
        end
      end
    end

    private

    def log(message)
      @logger&.info(message)
    end
  end
end
