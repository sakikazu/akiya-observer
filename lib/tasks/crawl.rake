namespace :crawl do
  def prompt_env(key, default: nil, required: false, type: :string, label: nil)
    env_value = ENV[key]
    return cast_value(env_value, type, key) if env_value

    unless $stdin.tty?
      return cast_value(default, type, key) if !required || !default.nil?
      raise ArgumentError, "#{key} is required"
    end

    label_text = label || key
    prompt = default.nil? ? label_text : "#{label_text} (デフォルト: #{default})"
    print "#{prompt}: "
    input = $stdin.gets&.strip
    value = input.nil? || input.empty? ? default : input
    if required && (value.nil? || value.to_s.strip.empty?)
      raise ArgumentError, "#{key} is required"
    end
    cast_value(value, type, key)
  end

  def cast_value(value, type, key)
    return nil if value.nil?

    case type
    when :float
      value.to_f
    when :integer
      value.to_i
    when :boolean
      return value if value == true || value == false
      normalized = value.to_s.strip.downcase
      return true if %w[true t yes y 1].include?(normalized)
      return false if %w[false f no n 0].include?(normalized)

      raise ArgumentError, "invalid boolean for #{key}: #{value}"
    else
      value.to_s
    end
  end

  desc "Crawl OK Smile listings via curl and save to DB (SEARCH_URL required)"
  task ok_smile: :environment do
    record_daily = prompt_env("DISAPPEAR_CHECK", default: "false", type: :boolean, label: "全件クロールして消失判定用に記録するか (true/false)")
    crawled_on = record_daily ? Date.current.to_s : nil
    crawl_record = nil
    collected_external_ids = []

    search_url = prompt_env(
      "SEARCH_URL",
      default: "https://www.ok-smile.jp/property/buy/area/list?prop-control=&sort1=ASRT13&sort2=&limit=100&ptm%5B%5D=9102&price_b_from=1000000&price_b_to=20000000&keyword=&eki_walk=&bus_walk=&land_from=&land_to=&bld_area_from=&bld_area_to=&built=",
      required: true,
      label: "検索URL (必須)"
    )
    fetch_detail = prompt_env("FETCH_DETAIL", default: "false", type: :boolean, label: "詳細ページも取得するか (true/false)")
    if record_daily
      download_images = false
      fetch_all = true
      start_page = 1
      max_pages = nil
    else
      download_images = prompt_env("DOWNLOAD_IMAGES", default: "false", type: :boolean, label: "画像をダウンロードするか (true/false)")
      fetch_all = prompt_env("FETCH_ALL", default: "false", type: :boolean, label: "全ページを取得するか (true/false)")
      start_page = fetch_all ? 1 : prompt_env("PAGE", default: "1", type: :integer, label: "開始ページ番号")
      max_pages = fetch_all ? nil : prompt_env("PAGES", default: "1", type: :integer, label: "取得するページ数")
    end

    if record_daily
      source_site = SourceSite.find_by!(code: "ok-smile")
      crawl_record = DailyCrawl.find_or_initialize_by(source_site: source_site, crawled_on: Date.parse(crawled_on))
      crawl_record.assign_attributes(
        status: "running",
        started_at: Time.current
      )
      crawl_record.save!
    end

    OkSmile::Crawler.new(
      search_url: search_url,
      fetch_detail: fetch_detail,
      download_images: download_images,
      fetch_all: fetch_all,
      start_page: start_page,
      max_pages: max_pages,
      on_listing: ->(listing) { collected_external_ids << listing.external_id if record_daily }
    ).call

    if record_daily && crawl_record
      crawl_record.assign_attributes(
        status: "completed",
        finished_at: Time.current,
        listing_count: collected_external_ids.uniq.size,
        external_ids: collected_external_ids.uniq
      )
      crawl_record.save!
    end
  rescue StandardError => e
    if record_daily && crawl_record
      crawl_record.update(status: "failed", finished_at: Time.current)
    end
    raise e
  end

  desc "Crawl OK Smile listings and then geocode (SEARCH_URL required)"
  task ok_smile_with_geocode: :environment do
    record_daily = prompt_env("DISAPPEAR_CHECK", default: "false", type: :boolean, label: "全件クロールして消失判定用に記録するか (true/false)")
    crawled_on = record_daily ? Date.current.to_s : nil
    crawl_record = nil
    collected_external_ids = []

    search_url = prompt_env(
      "SEARCH_URL",
      default: "https://www.ok-smile.jp/property/buy/area/list?prop-control=&sort1=ASRT13&sort2=&limit=100&ptm%5B%5D=9102&price_b_from=1000000&price_b_to=20000000&keyword=&eki_walk=&bus_walk=&land_from=&land_to=&bld_area_from=&bld_area_to=&built=",
      required: true,
      label: "検索URL (必須)"
    )
    geocode_limit = prompt_env("GEOCODE_LIMIT", default: "200", type: :integer, label: "ジオコーディング件数の上限")
    geocode_throttle = prompt_env("GEOCODE_THROTTLE", default: "1.0", type: :float, label: "ジオコーディング間の待機秒数")
    fetch_detail = prompt_env("FETCH_DETAIL", default: "false", type: :boolean, label: "詳細ページも取得するか (true/false)")
    download_images = prompt_env("DOWNLOAD_IMAGES", default: "false", type: :boolean, label: "画像をダウンロードするか (true/false)")
    fetch_all = prompt_env("FETCH_ALL", default: "false", type: :boolean, label: "全ページを取得するか (true/false)")
    start_page = fetch_all ? 1 : prompt_env("PAGE", default: "1", type: :integer, label: "開始ページ番号")
    max_pages = fetch_all ? nil : prompt_env("PAGES", default: "1", type: :integer, label: "取得するページ数")

    if record_daily
      source_site = SourceSite.find_by!(code: "ok-smile")
      crawl_record = DailyCrawl.find_or_initialize_by(source_site: source_site, crawled_on: Date.parse(crawled_on))
      crawl_record.assign_attributes(
        status: "running",
        started_at: Time.current
      )
      crawl_record.save!
    end

    OkSmile::Crawler.new(
      search_url: search_url,
      fetch_detail: fetch_detail,
      download_images: download_images,
      fetch_all: fetch_all,
      start_page: start_page,
      max_pages: max_pages,
      on_listing: ->(listing) { collected_external_ids << listing.external_id if record_daily }
    ).call

    if record_daily && crawl_record
      crawl_record.assign_attributes(
        status: "completed",
        finished_at: Time.current,
        listing_count: collected_external_ids.uniq.size,
        external_ids: collected_external_ids.uniq
      )
      crawl_record.save!
    end

    Geocoding::SourceListingGeocoder.new(throttle_seconds: geocode_throttle).call(limit: geocode_limit)
  rescue StandardError => e
    if record_daily && crawl_record
      crawl_record.update(status: "failed", finished_at: Time.current)
    end
    raise e
  end

  desc "Crawl Cocosma Ina listings via curl and save to DB (SEARCH_URL required)"
  task cocosma_ina: :environment do
    record_daily = prompt_env("DISAPPEAR_CHECK", default: "false", type: :boolean, label: "全件クロールして消失判定用に記録するか (true/false)")
    crawled_on = record_daily ? Date.current.to_s : nil
    crawl_record = nil
    collected_external_ids = []

    search_url = prompt_env(
      "SEARCH_URL",
      # 長野県伊那の500万円以上、間取り問わず、の中古物件、新着順の検索URL。
      default: "https://ina.fudousan.co.jp/lists/2/1/q?listtype=&area=&key=&ss=&sc=&k_l=500&k_h=&la_l=&la_h=&ll_l=&ll_h=&p_h=&k_d=&scode%5B1212%5D=%E4%B8%AD%E5%8F%A4%E4%BD%8F%E5%AE%85&scode%5B1223%5D=%E4%B8%AD%E5%8F%A4%E5%88%A5%E8%8D%98&dr=1&ev=1&rs=50",
      required: true,
      label: "検索URL (必須)"
    )
    if record_daily
      download_images = false
      fetch_all = true
      start_page = 1
      max_pages = nil
    else
      download_images = prompt_env("DOWNLOAD_IMAGES", default: "false", type: :boolean, label: "画像をダウンロードするか (true/false)")
      fetch_all = prompt_env("FETCH_ALL", default: "false", type: :boolean, label: "全ページを取得するか (true/false)")
      start_page = fetch_all ? 1 : prompt_env("PAGE", default: "1", type: :integer, label: "開始ページ番号")
      max_pages = fetch_all ? nil : prompt_env("PAGES", default: "1", type: :integer, label: "取得するページ数")
    end

    if record_daily
      source_site = SourceSite.find_or_create_by!(code: "cocosma-ina") do |site|
        site.name = "Cocosma Ina"
        site.base_url = "https://ina.fudousan.co.jp"
        site.active = true
      end
      crawl_record = DailyCrawl.find_or_initialize_by(source_site: source_site, crawled_on: Date.parse(crawled_on))
      crawl_record.assign_attributes(
        status: "running",
        started_at: Time.current
      )
      crawl_record.save!
    end

    CocosmaIna::Crawler.new(
      search_url: search_url,
      # 消失判定用の全クロールでは external_id 一覧だけあれば十分なため、詳細は取得しない。
      fetch_detail: !record_daily,
      download_images: download_images,
      fetch_all: fetch_all,
      start_page: start_page,
      max_pages: max_pages,
      on_listing: ->(listing) { collected_external_ids << listing.external_id if record_daily }
    ).call

    if record_daily && crawl_record
      crawl_record.assign_attributes(
        status: "completed",
        finished_at: Time.current,
        listing_count: collected_external_ids.uniq.size,
        external_ids: collected_external_ids.uniq
      )
      crawl_record.save!
    end
  rescue StandardError => e
    if record_daily && crawl_record
      crawl_record.update(status: "failed", finished_at: Time.current)
    end
    raise e
  end

  desc "Crawl Taketa City Akiya Bank listings via curl and save to DB"
  task taketa_iju: :environment do
    record_daily = prompt_env("DISAPPEAR_CHECK", default: "false", type: :boolean, label: "全件クロールして消失判定用に記録するか (true/false)")
    search_url = prompt_env(
      "SEARCH_URL",
      default: TaketaIju::HtmlImporter::DEFAULT_SEARCH_URL,
      required: true,
      label: "検索URL (必須)"
    )
    fetch_detail = record_daily ? false : prompt_env("FETCH_DETAIL", default: "true", type: :boolean, label: "詳細ページも取得するか (true/false)")
    download_images = record_daily ? false : prompt_env("DOWNLOAD_IMAGES", default: "true", type: :boolean, label: "メイン画像と間取り図をダウンロードするか (true/false)")
    source_site = SourceSite.find_or_create_by!(code: "taketa-iju") do |site|
      site.name = "竹田市空き家バンク"
      site.base_url = TaketaIju::HtmlImporter::DEFAULT_BASE_URL
      site.search_url = search_url
      site.active = true
    end
    crawl_record = nil
    collected_external_ids = []

    if record_daily
      crawl_record = DailyCrawl.find_or_initialize_by(source_site: source_site, crawled_on: Date.current)
      crawl_record.assign_attributes(status: "running", started_at: Time.current)
      crawl_record.save!
    end

    TaketaIju::Crawler.new(
      search_url: search_url,
      fetch_detail: fetch_detail,
      download_images: download_images,
      on_listing: ->(listing) { collected_external_ids << listing.external_id if record_daily }
    ).call

    if crawl_record
      crawl_record.update!(
        status: "completed",
        finished_at: Time.current,
        listing_count: collected_external_ids.uniq.size,
        external_ids: collected_external_ids.uniq
      )
    end
  rescue StandardError => e
    crawl_record&.update(status: "failed", finished_at: Time.current)
    raise e
  end
end
