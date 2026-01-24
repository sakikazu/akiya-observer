namespace :crawl do
  def prompt_env(key, default: nil, required: false, type: :string, label: nil)
    env_value = ENV[key]
    return cast_value(env_value, type, key) if env_value

    unless $stdin.tty?
      return default unless required
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
    search_url = prompt_env("SEARCH_URL", required: true, label: "検索URL (必須)")
    fetch_detail = prompt_env("FETCH_DETAIL", default: "false", type: :boolean, label: "詳細ページも取得するか (true/false)")
    download_images = prompt_env("DOWNLOAD_IMAGES", default: "false", type: :boolean, label: "画像をダウンロードするか (true/false)")
    fetch_all = prompt_env("FETCH_ALL", default: "false", type: :boolean, label: "全ページを取得するか (true/false)")
    start_page = prompt_env("PAGE", default: "1", type: :integer, label: "開始ページ番号")
    max_pages = prompt_env("PAGES", default: "1", type: :integer, label: "取得するページ数")

    OkSmile::Crawler.new(
      search_url: search_url,
      fetch_detail: fetch_detail,
      download_images: download_images,
      fetch_all: fetch_all,
      start_page: start_page,
      max_pages: max_pages
    ).call
  end

  desc "Crawl OK Smile listings and then geocode (SEARCH_URL required)"
  task ok_smile_with_geocode: :environment do
    search_url = prompt_env("SEARCH_URL", required: true, label: "検索URL (必須)")
    geocode_limit = prompt_env("GEOCODE_LIMIT", default: "200", type: :integer, label: "ジオコーディング件数の上限")
    geocode_throttle = prompt_env("GEOCODE_THROTTLE", default: "1.0", type: :float, label: "ジオコーディング間の待機秒数")
    fetch_detail = prompt_env("FETCH_DETAIL", default: "false", type: :boolean, label: "詳細ページも取得するか (true/false)")
    download_images = prompt_env("DOWNLOAD_IMAGES", default: "false", type: :boolean, label: "画像をダウンロードするか (true/false)")
    fetch_all = prompt_env("FETCH_ALL", default: "false", type: :boolean, label: "全ページを取得するか (true/false)")
    start_page = prompt_env("PAGE", default: "1", type: :integer, label: "開始ページ番号")
    max_pages = prompt_env("PAGES", default: "1", type: :integer, label: "取得するページ数")

    OkSmile::Crawler.new(
      search_url: search_url,
      fetch_detail: fetch_detail,
      download_images: download_images,
      fetch_all: fetch_all,
      start_page: start_page,
      max_pages: max_pages
    ).call

    Geocoding::SourceListingGeocoder.new(throttle_seconds: geocode_throttle).call(limit: geocode_limit)
  end
end
