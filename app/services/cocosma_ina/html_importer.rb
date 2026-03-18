require "date"
require "fileutils"
require "logger"
require "net/http"
require "nokogiri"
require "securerandom"
require "uri"

module CocosmaIna
  # ココスマ伊那の一覧/詳細HTMLから物件情報を取り込む。
  class HtmlImporter < OkSmile::HtmlImporter
    DEFAULT_BASE_URL = "https://ina.fudousan.co.jp".freeze
    DEFAULT_DETAIL_DIR = Rails.root.join("tmp", "cocosma_ina_details").to_s
    IMAGE_STORAGE_ROOT = "storage/listing_images/cocosma_ina".freeze

    def initialize(list_path: nil, detail_dir: DEFAULT_DETAIL_DIR, source_site_code: "cocosma-ina", base_url: DEFAULT_BASE_URL, **kwargs)
      super(list_path: list_path, detail_dir: detail_dir, source_site_code: source_site_code, base_url: base_url, **kwargs)
    end

    def call
      raise ArgumentError, "list_path is required for HtmlImporter" if @list_path.nil?

      doc = Nokogiri::HTML(File.read(@list_path))
      source_site = find_or_create_source_site

      nodes = list_nodes(doc)
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
        site.name = "Cocosma Ina"
        site.base_url = @base_url
        site.active = true
      end
    end

    def list_nodes(doc)
      doc.css(".detailListBox")
    end

    def upsert_from_list(node, source_site)
      detail_href = node.at_css("h2.title a")&.[]("href")
      detail_url = detail_href ? URI.join(@base_url, detail_href).to_s : nil
      external_id = extract_external_id(detail_url, node)
      raise ArgumentError, "external_id not found in list node" if external_id.blank?

      title = clean_text(node.at_css("h2.title a")&.text)
      summary = parse_list_summary(node)
      tags = extract_tags(node)
      address = extract_address_from_title(title)

      prefecture = Prefecture.find_by(code: "20")
      municipality_text = address.presence || title
      municipality = Municipality.find_by_text_match(municipality_text, prefecture: prefecture)
      log("municipality not matched for listing #{external_id} (title: #{title})") if municipality.nil?

      listing = SourceListing.find_or_initialize_by(source_site: source_site, external_id: external_id)
      listing.assign_attributes(
        url: detail_url,
        title: title.presence,
        price: parse_price(summary["価格"]),
        tag_list: tags.join(","),
        layout: summary["間取"].presence,
        land_area: summary["土地面積"].presence,
        building_area: summary["建物面積"].presence,
        address: address.presence || listing.address,
        municipality_id: municipality&.id || listing.municipality_id,
        first_seen_at: listing.first_seen_at || Time.current,
        last_seen_at: Time.current,
        last_checked_at: Time.current
      )
      listing.extra_payload = merge_payload(listing.extra_payload, {
        "list_summary" => summary,
        "list_description" => clean_text(node.at_css("p.desc")&.text)
      })
      listing.save!

      log("listing #{external_id} saved (title: #{listing.title})")
      update_images_from_list(listing, node)
      listing
    end

    def update_from_detail(listing, doc)
      info = parse_info_table(doc)
      address = info["所在地"]
      latitude, longitude = parse_map_coordinates(doc)
      built_year_month = info["完成年月日"].presence || extract_built_year_month(info["備考"])
      source_updated_at = parse_dash_date(info["最終更新日"])
      tags = extract_tags(doc)

      municipality = if address.present?
        Municipality.find_by_text_match(address, prefecture: Prefecture.find_by(code: "20"))
      end

      listing.assign_attributes(
        title: clean_text(doc.at_css("#detailSummary h1 .text")&.text).presence || listing.title,
        price: parse_price(info["価格"]) || listing.price,
        built_year_month: built_year_month.presence || listing.built_year_month,
        layout: info["間取"].presence || listing.layout,
        land_area: info["土地面積"].presence || listing.land_area,
        building_area: info["建物面積"].presence || listing.building_area,
        structure: info["建物構造"].presence || listing.structure,
        zoning: info["用途地域"].presence || listing.zoning,
        building_coverage_ratio: info["建ぺい率"].presence || listing.building_coverage_ratio,
        floor_area_ratio: info["容積率"].presence || listing.floor_area_ratio,
        source_updated_at: source_updated_at || listing.source_updated_at,
        address: address.presence || listing.address,
        address_precision: address_precision(address.presence || listing.address),
        latitude: latitude || listing.latitude,
        longitude: longitude || listing.longitude,
        municipality_id: municipality&.id || listing.municipality_id,
        tag_list: merge_tags(listing.tag_list, tags).join(","),
        last_checked_at: Time.current
      )
      listing.extra_payload = merge_payload(listing.extra_payload, {
        "detail_info" => info,
        "detail_description" => clean_text(doc.at_css("#detailSummary p.desc")&.text)
      })
      listing.save!

      log("listing #{listing.external_id} detail updated")
      update_images_from_detail(listing, doc)
    end

    def parse_list_summary(node)
      node.css(".summary dl.define").each_with_object({}) do |dl, info|
        dts = dl.css("dt")
        dds = dl.css("dd")
        dts.zip(dds).each do |dt, dd|
          label = clean_text(dt.text)
          value = clean_text(dd.text)
          next if label.empty?

          info[label] = value
        end
      end
    end

    def parse_info_table(doc)
      doc.css("table.tableStyleB tr").each_with_object({}) do |row, info|
        label = clean_text(row.at_css("th")&.text)
        value = clean_text(row.at_css("td")&.text)
        next if label.empty?

        info[label] = value
      end
    end

    def parse_map_coordinates(doc)
      href = doc.at_css("#detailMap a[href*='maps.google.co.jp/?q=']")&.[]("href")
      href ||= doc.at_css("#detailMap iframe")&.[]("src")
      return [nil, nil] if href.to_s.strip.empty?

      uri = URI.parse(href.start_with?("//") ? "https:#{href}" : href)
      params = URI.decode_www_form(uri.query.to_s).to_h
      coords = params["q"].to_s.split(",").map(&:strip)
      return [nil, nil] if coords.size < 2

      [coords[0].to_f, coords[1].to_f]
    rescue URI::InvalidURIError
      [nil, nil]
    end

    def extract_tags(node)
      node.css(".label").map { |tag| clean_text(tag.text) }.reject(&:empty?).uniq
    end

    def update_images_from_list(listing, node)
      url = node.at_css(".thumb img")&.[]("src")
      return if url.blank?

      upsert_images(listing, [normalize_image_url(url)], reset_main: false)
    end

    def update_images_from_detail(listing, doc)
      urls = doc.css("#detailPhotoGallery a").map { |link| link["href"].presence || link.at_css("img")&.[]("src") }
      urls = urls.compact.map { |url| normalize_image_url(url) }.uniq
      return if urls.empty?

      log("listing #{listing.external_id} detail images: #{urls.size}")
      upsert_images(listing, urls, reset_main: true)
    end

    def image_storage_path(listing, remote_url)
      uri = URI.parse(remote_url)
      filename = File.basename(uri.path)
      filename = "#{SecureRandom.hex(8)}.jpg" if filename.blank? || filename == "/"
      File.join(IMAGE_STORAGE_ROOT, listing.external_id.to_s, filename)
    rescue URI::InvalidURIError
      File.join(IMAGE_STORAGE_ROOT, listing.external_id.to_s, "#{SecureRandom.hex(8)}.jpg")
    end

    def detail_path_for(external_id)
      return if external_id.blank?

      File.join(@detail_dir, "cocosma-ina-detail-#{external_id}.html")
    end

    def parse_list_updated_at(node)
      text = clean_text(node.at_css(".boxB small, .boxC small, small")&.text)
      match = text.match(/最終更新日\s+(\d{4}\.\d{2}\.\d{2})/)
      return if match.nil?

      Date.strptime(match[1], "%Y.%m.%d").to_time
    rescue Date::Error
      nil
    end

    private

    def extract_external_id(detail_url, node)
      return Regexp.last_match(1) if detail_url.to_s.match(%r{/details/(\d+)})

      checkbox = node.at_css("input.js-checkbox")
      checkbox&.[]("value").to_s.strip
    end

    def extract_address_from_title(title)
      clean = clean_text(title)
      return if clean.empty?

      clean.sub(/\s+[^[:space:]]+\z/, "")
    end

    def normalize_image_url(url)
      URI.join(@base_url, url).to_s
    rescue URI::InvalidURIError
      url
    end

    def parse_dash_date(value)
      return if value.to_s.strip.empty?

      Date.strptime(value, "%Y-%m-%d")
    rescue Date::Error
      nil
    end

    def extract_built_year_month(text)
      return if text.to_s.strip.empty?

      match = text.match(/(?:築年月|完成年月日|完成年月)[:：]?\s*(\d{4}年\d{1,2}月)/)
      match&.[](1)
    end

    def pr_listing?(node)
      node.at_css(".icon-pr").present?
    end
  end
end
