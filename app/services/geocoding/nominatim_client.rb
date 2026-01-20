require "json"
require "net/http"
require "uri"

module Geocoding
  # Nominatim のジオコーディングを最小限に呼び出すクライアント。
  class NominatimClient
    DEFAULT_BASE_URL = "https://nominatim.openstreetmap.org/search"
    # Nominatim は User-Agent の明示が必須。
    DEFAULT_USER_AGENT = "akiya-observer/1.0 (contact: local)"

    def initialize(base_url: DEFAULT_BASE_URL, user_agent: DEFAULT_USER_AGENT)
      @base_url = base_url
      @user_agent = user_agent
    end

    # { latitude:, longitude: } を返す。該当なしは nil。
    def geocode(address)
      return if address.to_s.strip.empty?

      uri = URI(@base_url)
      uri.query = URI.encode_www_form(q: address, format: "json", limit: 1, addressdetails: 0)

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        request = Net::HTTP::Get.new(uri.request_uri)
        request["User-Agent"] = @user_agent
        http.request(request)
      end

      return unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      return if data.empty?

      { latitude: data[0]["lat"].to_f, longitude: data[0]["lon"].to_f }
    rescue JSON::ParserError
      nil
    end
  end
end
