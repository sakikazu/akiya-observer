require "nokogiri"

module TaketaIju
  # 竹田市空き家バンクの一覧と売買物件の詳細をcurlで取得する。
  class Crawler < HtmlImporter
    DEFAULT_REQUEST_SLEEP_RANGE = (1.0..3.0)
    REQUEST_TIMEOUT_SECONDS = 15

    def initialize(search_url: DEFAULT_SEARCH_URL, fetch_detail: true, request_sleep_range: DEFAULT_REQUEST_SLEEP_RANGE, on_listing: nil, **kwargs)
      super(request_sleep_range: request_sleep_range, **kwargs)
      @search_url = search_url
      @fetch_detail = fetch_detail
      @on_listing = on_listing
      @curl_client = HtmlFetching::CurlClient.new(
        user_agent: @user_agent,
        timeout_seconds: REQUEST_TIMEOUT_SECONDS,
        logger: @logger,
        sleep_range: request_sleep_range
      )
    end

    def call
      source_site = find_or_create_source_site
      log("request #{@search_url}")
      doc = Nokogiri::HTML(fetch_html(@search_url, referer: @base_url))
      nodes = listing_nodes(doc)
      log("Found #{nodes.size} listings")

      nodes.each_with_index do |node, index|
        listing = upsert_from_list(node, source_site)
        @on_listing&.call(listing)
        next unless @fetch_detail && listing.url.present?

        log("[#{index + 1}/#{nodes.size}] request #{listing.url}")
        detail_doc = Nokogiri::HTML(fetch_html(listing.url, referer: @search_url))
        update_from_detail(listing, detail_doc)
      end

      log("total requests: #{@request_count}")
    end

    private

    def fetch_html(url, referer:)
      increment_request_count
      @curl_client.fetch(url, referer: referer)
    end
  end
end
