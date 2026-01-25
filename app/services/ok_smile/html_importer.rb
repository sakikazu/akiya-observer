require "date"
require "fileutils"
require "logger"
require "net/http"
require "nokogiri"
require "securerandom"
require "uri"

module OkSmile
  # OK Smile の保存済みHTMLから物件情報と画像を取り込む。
  class HtmlImporter
    DEFAULT_BASE_URL = "https://www.ok-smile.jp"
    DEFAULT_DETAIL_DIR = "/tmp"
    REQUEST_TIMEOUT_SECONDS = 5
    # 取り込み結果の画像はリポジトリ内のストレージに保存する。
    IMAGE_STORAGE_ROOT = "storage/listing_images/ok_smile"
    # 画像取得ごとに待機を入れて負荷を抑える。
    DEFAULT_THROTTLE_SECONDS = 1.0
    DEFAULT_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36"
    IGNORE_TAG_CLASSES = %w[icon_img_count history_icon view-count icon_new].freeze

    def initialize(list_path: nil, detail_dir: DEFAULT_DETAIL_DIR, source_site_code: "ok-smile", base_url: DEFAULT_BASE_URL, throttle_seconds: DEFAULT_THROTTLE_SECONDS, logger: nil, user_agent: DEFAULT_USER_AGENT, download_images: true, request_sleep_range: (1.0..3.0), prefecture_code: nil)
      @list_path = list_path
      @detail_dir = detail_dir
      @source_site_code = source_site_code
      @base_url = base_url
      @throttle_seconds = throttle_seconds
      @logger = logger || Logger.new($stdout)
      @user_agent = user_agent
      @download_images = download_images
      @request_sleep_range = request_sleep_range
      @request_count = 0
      @prefecture_code = prefecture_code
    end

    def call
      raise ArgumentError, "list_path is required for HtmlImporter" if @list_path.nil?

      doc = Nokogiri::HTML(File.read(@list_path))
      source_site = find_or_create_source_site

      nodes = doc.css("li.list-group-item[data-id]")
      log("Found #{nodes.size} listings in #{@list_path}")

      nodes.each_with_index do |node, index|
        listing = upsert_from_list(node, source_site)
        detail_path = detail_path_for(listing.external_id)
        if detail_path && File.exist?(detail_path)
          log("[#{index + 1}/#{nodes.size}] detail: #{detail_path}")
        else
          log("[#{index + 1}/#{nodes.size}] detail: missing for #{listing.external_id}")
          next
        end

        detail_doc = Nokogiri::HTML(File.read(detail_path))
        update_from_detail(listing, detail_doc)
      end
    end

    protected

    def find_or_create_source_site
      SourceSite.find_or_create_by!(code: @source_site_code) do |site|
        site.name = "OK Smile"
        site.base_url = @base_url
        site.active = true
      end
    end

    def upsert_from_list(node, source_site)
      external_id = node["data-id"].to_s.strip
      detail_href = node.at_css("a.prop-title-link")&.[]("href")
      detail_url = detail_href ? URI.join(@base_url, detail_href).to_s : nil

      title = node.css("a.prop-title-link span.prop-title-link").map { |span| clean_text(span.text) }
        .reject(&:empty?).join(" ")
      # 物件タイトルから市区町村名を抽出して紐付ける（県スコープあり）。
      access = clean_text(node.at_css(".access")&.text)
      price = parse_price(node.at_css(".price strong")&.text)
      tags = extract_tags(node)
      list_info = parse_list_info(node)
      source_updated_at = parse_unix_timestamp(node["data-upd-time"])
      lat, lng = parse_map_coordinates(node)

      prefecture = Prefecture.find_by(code: @prefecture_code) if @prefecture_code.present?
      municipality = Municipality.find_by_text_match(title, prefecture: prefecture)
      log("municipality not matched for listing #{external_id} (title: #{title})") if municipality.nil?

      listing = SourceListing.find_or_initialize_by(source_site: source_site, external_id: external_id)
      listing.assign_attributes(
        url: detail_url,
        title: title.presence,
        price: price,
        tag_list: tags.join(","),
        layout: list_info[:layout],
        land_area: list_info[:land_area],
        building_area: list_info[:building_area],
        structure: list_info[:structure],
        zoning: list_info[:zoning],
        building_coverage_ratio: list_info[:building_coverage_ratio],
        floor_area_ratio: list_info[:floor_area_ratio],
        source_updated_at: source_updated_at,
        municipality_id: municipality&.id,
        latitude: lat || listing.latitude,
        longitude: lng || listing.longitude,
        first_seen_at: listing.first_seen_at || Time.current,
        last_seen_at: Time.current,
        last_checked_at: Time.current
      )
      listing.extra_payload = merge_payload(listing.extra_payload, { "access" => access })
      listing.save!

      log("listing #{external_id} saved (title: #{listing.title})")
      update_images_from_list(listing, node)

      listing
    end

    # 詳細ページには住所や建ぺい率などの追加情報がある。
    def update_from_detail(listing, doc)
      info = parse_info_table(doc)
      coverage_ratio, floor_ratio = parse_coverage_ratio(info["建ぺい率・容積率"])
      source_updated_at = parse_jp_date(info["情報更新日"])
      access = info["交通"]
      address = info["所在地"]

      tags = extract_tags(doc)

      listing.assign_attributes(
        built_year_month: info["築年月"].presence || listing.built_year_month,
        layout: info["間取り"].presence || listing.layout,
        land_area: info["土地面積"].presence || listing.land_area,
        building_area: info["建物面積"].presence || listing.building_area,
        structure: info["建物構造"].presence || listing.structure,
        zoning: info["用途地域"].presence || listing.zoning,
        building_coverage_ratio: coverage_ratio.presence || listing.building_coverage_ratio,
        floor_area_ratio: floor_ratio.presence || listing.floor_area_ratio,
        source_updated_at: source_updated_at || listing.source_updated_at,
        address: address.presence || listing.address,
        address_precision: address_precision(address),
        tag_list: merge_tags(listing.tag_list, tags).join(","),
        last_checked_at: Time.current
      )
      listing.extra_payload = merge_payload(listing.extra_payload, { "detail_info" => info, "access" => access })
      listing.save!

      log("listing #{listing.external_id} detail updated")
      update_images_from_detail(listing, doc)
    end

    def parse_list_info(node)
      info = {}
      node.css(".list-info li").each do |item|
        label = clean_text(item.at_css(".icon.info")&.text)
        value = clean_text(item.at_css(".value.info")&.text)
        next if label.empty?

        case label
        when "間取り"
          info[:layout] = value
        when "土地面積"
          info[:land_area] = value
        when "建物面積"
          info[:building_area] = value
        when "建物構造"
          info[:structure] = value
        when "用途地域"
          info[:zoning] = value
        when "建・容率"
          info[:building_coverage_ratio], info[:floor_area_ratio] = parse_coverage_ratio(value)
        end
      end
      info
    end

    # 一覧の map リンクから緯度経度を取得する。
    def parse_map_coordinates(node)
      href = node.at_css("a.map-icon")&.[]("href")
      return [nil, nil] if href.to_s.strip.empty?

      uri = URI.parse(href)
      params = URI.decode_www_form(uri.query.to_s).to_h
      coords = params["q"].to_s.split(",").map(&:strip)
      return [nil, nil] if coords.size < 2

      [coords[0].to_f, coords[1].to_f]
    rescue URI::InvalidURIError
      [nil, nil]
    end

    def parse_info_table(doc)
      info = {}
      doc.css("table.info-table tr").each do |row|
        label = clean_text(row.at_css(".info-label")&.text)
        value = clean_text(row.at_css(".info-val")&.text)
        next if label.empty?

        info[label] = value
      end
      info
    end

    def parse_price(text)
      value = clean_text(text)
      return if value.empty?

      if value.include?("万円")
        numeric = value.delete("^0-9.")
        (numeric.to_f * 10_000).to_i
      else
        value.delete("^0-9").to_i
      end
    end

    def parse_unix_timestamp(value)
      return if value.to_s.strip.empty?

      Time.at(value.to_i)
    end

    def parse_jp_date(value)
      return if value.to_s.strip.empty?

      if value =~ /(\d{4})年(\d{1,2})月(\d{1,2})日/
        Date.new(Regexp.last_match(1).to_i, Regexp.last_match(2).to_i, Regexp.last_match(3).to_i)
      end
    end

    # 建ぺい率・容積率の表記ゆれ（60%/200% など）を2項目に分解する。
    def parse_coverage_ratio(value)
      cleaned = clean_text(value)
      return [nil, nil] if cleaned.empty?

      parts = cleaned.split(/[\/／]/).map(&:strip)
      if parts.size == 2
        [parts[0], parts[1]]
      else
        [cleaned, nil]
      end
    end

    # 物件タグは .prop-icon に出るため、UI専用バッジを除外する。
    def extract_tags(node)
      node.css(".prop-icon").map do |tag|
        next if (tag["class"].to_s.split & IGNORE_TAG_CLASSES).any?

        clean_text(tag.text)
      end.compact.reject(&:empty?).uniq
    end

    def merge_tags(existing, incoming)
      current = existing.to_s.split(",").map(&:strip).reject(&:empty?)
      (current + incoming).uniq
    end

    # 一覧ページはサムネイル1枚のみ取得する。
    def update_images_from_list(listing, node)
      image = node.at_css("img.prop-img")
      return unless image

      url = image["data-echo"].presence || image["src"].presence
      return if url.blank?

      log("listing #{listing.external_id} list image: #{url}")
      upsert_images(listing, [url], reset_main: false)
    end

    # 詳細ページは全画像のカルーセルを取得する。
    def update_images_from_detail(listing, doc)
      urls = doc.css("img.main-slider-image").map do |image|
        image["data-lazy"].presence || image["src"].presence
      end.compact

      return if urls.empty?

      log("listing #{listing.external_id} detail images: #{urls.size}")
      upsert_images(listing, urls, reset_main: true)
    end

    def upsert_images(listing, urls, reset_main:)
      listing.listing_images.update_all(is_main: false) if reset_main

      urls.compact.uniq.each_with_index do |url, index|
        image = listing.listing_images.find_or_initialize_by(remote_url: url)
        image.position = index + 1
        image.is_main = index.zero?
        download_image(listing, image) if @download_images
        image.save!
      end
    end

    # 画像取得が200以外なら中断し、欠損取り込みを避ける。
    def download_image(listing, image)
      return if image.remote_url.blank?

      path = image_storage_path(listing, image.remote_url)
      absolute_path = Rails.root.join(path)
      return if File.exist?(absolute_path)

      FileUtils.mkdir_p(File.dirname(absolute_path))
      increment_request_count
      log("request #{image.remote_url}")
      response = fetch_with_redirects(image.remote_url)
      sleep_random
      unless response&.is_a?(Net::HTTPSuccess)
        code = response&.code || "unknown"
        message = "image download failed (#{code}) for #{image.remote_url}"
        log(message)
        raise StandardError, message
      end

      File.binwrite(absolute_path, response.body)
      image.local_path = path
      image.downloaded_at = Time.current
      image.content_type = response["content-type"]
      image.filesize = response.body.bytesize
      log("downloaded image to #{path}")
    end

    # 画像CDNのリダイレクトに備えて少数回だけ追従する。
    def fetch_with_redirects(url, limit = 3)
      return if limit.negative?

      log("リクエスト実行: #{url}")
      uri = URI.parse(url)
      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: REQUEST_TIMEOUT_SECONDS,
        read_timeout: REQUEST_TIMEOUT_SECONDS
      ) do |http|
        request = Net::HTTP::Get.new(uri.request_uri)
        request["User-Agent"] = @user_agent
        request["Referer"] = @base_url
        request["Accept"] = "image/avif,image/webp,image/apng,image/*,*/*;q=0.8"
        http.request(request)
      end

      case response
      when Net::HTTPRedirection
        fetch_with_redirects(response["location"], limit - 1)
      else
        response
      end
    end

    # external_id単位で画像を保存する。
    def image_storage_path(listing, remote_url)
      uri = URI.parse(remote_url)
      filename = File.basename(uri.path)
      filename = "#{SecureRandom.hex(8)}.jpg" if filename.blank? || filename == "/"
      File.join(IMAGE_STORAGE_ROOT, listing.external_id.to_s, filename)
    rescue URI::InvalidURIError
      File.join(IMAGE_STORAGE_ROOT, listing.external_id.to_s, "#{SecureRandom.hex(8)}.jpg")
    end

    def merge_payload(existing_payload, new_payload)
      existing_hash = existing_payload.is_a?(Hash) ? existing_payload : {}
      existing_hash.merge(new_payload.compact)
    end

    def clean_text(text)
      text.to_s.gsub("\u00a0", " ").gsub(/\s+/, " ").strip
    end

    # 住所末尾が数字なら番地ありと判定する簡易ルール。
    def address_precision(address)
      return if address.to_s.strip.empty?

      address.to_s.strip.match?(/\d\z/) ? "block" : "area"
    end

    def log(message)
      @logger&.info(message)
    end

    def increment_request_count
      @request_count += 1
    end

    def sleep_random
      range = @request_sleep_range
      return unless range

      sleep(rand(range))
    end

    def detail_path_for(external_id)
      return if external_id.blank?

      File.join(@detail_dir, "ok-smile-detail-#{external_id}.html")
    end
  end
end
