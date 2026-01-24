namespace :crawl do
  desc "Crawl OK Smile listings via curl and save to DB (SEARCH_URL required)"
  task ok_smile: :environment do
    search_url = ENV.fetch("SEARCH_URL")
    throttle = ENV.fetch("THROTTLE", "1.0").to_f
    page_throttle = ENV.fetch("PAGE_THROTTLE", "1.0").to_f
    fetch_detail = ENV.fetch("FETCH_DETAIL", "false").casecmp("true").zero?
    download_images = ENV.fetch("DOWNLOAD_IMAGES", "true").casecmp("true").zero?
    fetch_all = ENV.fetch("FETCH_ALL", "false").casecmp("true").zero?
    start_page = ENV.fetch("PAGE", "1").to_i
    max_pages = ENV["PAGES"]&.to_i

    OkSmile::Crawler.new(
      search_url: search_url,
      throttle_seconds: throttle,
      page_throttle_seconds: page_throttle,
      fetch_detail: fetch_detail,
      download_images: download_images,
      fetch_all: fetch_all,
      start_page: start_page,
      max_pages: max_pages
    ).call
  end

  desc "Crawl OK Smile listings and then geocode (SEARCH_URL required)"
  task ok_smile_with_geocode: :environment do
    search_url = ENV.fetch("SEARCH_URL")
    throttle = ENV.fetch("THROTTLE", "1.0").to_f
    page_throttle = ENV.fetch("PAGE_THROTTLE", "1.0").to_f
    geocode_limit = ENV.fetch("GEOCODE_LIMIT", "200").to_i
    geocode_throttle = ENV.fetch("GEOCODE_THROTTLE", "1.0").to_f
    fetch_detail = ENV.fetch("FETCH_DETAIL", "false").casecmp("true").zero?
    download_images = ENV.fetch("DOWNLOAD_IMAGES", "true").casecmp("true").zero?
    fetch_all = ENV.fetch("FETCH_ALL", "false").casecmp("true").zero?
    start_page = ENV.fetch("PAGE", "1").to_i
    max_pages = ENV["PAGES"]&.to_i

    OkSmile::Crawler.new(
      search_url: search_url,
      throttle_seconds: throttle,
      page_throttle_seconds: page_throttle,
      fetch_detail: fetch_detail,
      download_images: download_images,
      fetch_all: fetch_all,
      start_page: start_page,
      max_pages: max_pages
    ).call

    Geocoding::SourceListingGeocoder.new(throttle_seconds: geocode_throttle).call(limit: geocode_limit)
  end
end
