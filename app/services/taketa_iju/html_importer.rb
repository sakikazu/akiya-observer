require "date"
require "logger"
require "nokogiri"
require "uri"

module TaketaIju
  # 竹田市空き家バンクの公開HTMLから売買物件を取り込む。
  class HtmlImporter < OkSmile::HtmlImporter
    DEFAULT_BASE_URL = "https://taketa-iju.com".freeze
    DEFAULT_SEARCH_URL = "https://taketa-iju.com/house/".freeze
    DEFAULT_DETAIL_DIR = Rails.root.join("tmp", "taketa_iju_details").to_s
    MUNICIPALITY_CODE = "442089".freeze
    IMAGE_STORAGE_ROOT = "storage/listing_images/taketa_iju".freeze

    def initialize(list_path: nil, detail_dir: DEFAULT_DETAIL_DIR, source_site_code: "taketa-iju", base_url: DEFAULT_BASE_URL, **kwargs)
      super(list_path: list_path, detail_dir: detail_dir, source_site_code: source_site_code, base_url: base_url, **kwargs)
    end

    def call
      raise ArgumentError, "list_path is required for HtmlImporter" if @list_path.nil?

      doc = Nokogiri::HTML(File.read(@list_path))
      source_site = find_or_create_source_site
      nodes = listing_nodes(doc)
      log("Found #{nodes.size} listings in #{@list_path}")

      nodes.each_with_index do |node, index|
        listing = upsert_from_list(node, source_site)
        detail_path = detail_path_for(listing.external_id)
        unless detail_path && File.exist?(detail_path)
          log("[#{index + 1}/#{nodes.size}] detail: missing for #{listing.external_id}")
          next
        end

        update_from_detail(listing, Nokogiri::HTML(File.read(detail_path)))
      end
    end

    protected

    def find_or_create_source_site
      SourceSite.find_or_create_by!(code: @source_site_code) do |site|
        site.name = "竹田市空き家バンク"
        site.base_url = @base_url
        site.search_url = DEFAULT_SEARCH_URL
        site.active = true
      end
    end

    # 売買・賃貸の種別が明示された物件だけを返す。
    def listing_nodes(doc)
      doc.css("ul.searchList > li").select { |node| transaction_type(node).present? }
    end

    def transaction_type(node)
      value = clean_text(node.at_css(".searchType")&.text)
      return "sale_and_rent" if value.include?("売買") && value.include?("賃貸")
      return "sale" if value.include?("売買")
      "rent" if value.include?("賃貸")
    end

    def upsert_from_list(node, source_site)
      external_id = clean_text(node.at_css("p.listNumber")&.text)[/\d+/]
      raise ArgumentError, "external_id not found in list node" if external_id.blank?

      detail_href = node.at_css("a[href]")&.[]("href")
      detail_url = detail_href ? URI.join(@base_url, detail_href).to_s : nil
      area = clean_text(node.at_css(".searchAdd")&.text)
      price_text = clean_text(node.at_css(".searchPrice")&.text)
      listing_transaction_type = transaction_type(node)
      layout = list_layout(node)
      tags = extract_taketa_tags(node)
      municipality = taketa_municipality

      listing = SourceListing.find_or_initialize_by(source_site: source_site, external_id: external_id)
      listing.assign_attributes(
        url: detail_url,
        title: "No.#{external_id} #{area}".strip,
        price: listing_transaction_type == "rent" ? nil : parse_sale_price(price_text),
        monthly_rent: listing_transaction_type == "sale" ? nil : parse_monthly_rent(price_text),
        transaction_type: listing_transaction_type,
        tag_list: tags.join(","),
        layout: layout.presence,
        land_area: extract_area(node.at_css(".searchArea")&.text),
        municipality: municipality,
        first_seen_at: listing.first_seen_at || Time.current,
        last_seen_at: Time.current,
        last_checked_at: Time.current
      )
      listing.extra_payload = merge_payload(listing.extra_payload, {
        "area_name" => area,
        "list_price_text" => price_text
      })
      listing.save!

      update_images_from_list(listing, node)
      log("listing #{external_id} saved (title: #{listing.title})")
      listing
    end

    def update_from_detail(listing, doc)
      info = parse_taketa_info_table(doc)
      address = normalize_address(info["物件所在地"])
      title = clean_text(doc.at_css(".searchTtlSub .ttl")&.text)
      price_text = clean_text(doc.at_css(".searchListSub .searchPrice")&.text)
      listing_transaction_type = transaction_type(doc.at_css(".searchTtlSub") || doc)
      listing_transaction_type ||= listing.transaction_type

      listing.assign_attributes(
        title: title.presence || listing.title,
        price: listing_transaction_type == "rent" ? nil : (parse_sale_price(price_text) || listing.price),
        monthly_rent: listing_transaction_type == "sale" ? nil : (parse_monthly_rent(price_text) || listing.monthly_rent),
        transaction_type: listing_transaction_type,
        built_year_month: info["建築時期"].presence || listing.built_year_month,
        layout: info["間取り"].presence || listing.layout,
        land_area: info["敷地面積"].presence || listing.land_area,
        building_area: info["延床面積"].presence || listing.building_area,
        structure: info["構造"].presence || listing.structure,
        source_updated_at: parse_jp_date(info["更新日"]) || listing.source_updated_at,
        address: address.presence || listing.address,
        address_precision: "area",
        municipality: taketa_municipality,
        tag_list: extract_taketa_tags(doc.at_css(".searchListSub") || doc).join(","),
        last_checked_at: Time.current
      )
      listing.extra_payload = merge_payload(listing.extra_payload, {
        "detail_info" => info,
        "owner_voice" => clean_text(doc.at_css(".ownerVoice")&.text),
        "detail_price_text" => price_text
      })
      listing.save!

      update_images_from_detail(listing, doc)
      log("listing #{listing.external_id} detail updated")
      listing
    end

    def parse_taketa_info_table(doc)
      doc.css("table.table01 tr").each_with_object({}) do |row, info|
        label = clean_text(row.at_css("th")&.text)
        next if label.empty?

        info[label] = clean_text(row.at_css("td")&.text)
      end
    end

    # 売買・賃貸併記や値下げ表記から、売買側の現在価格を円で返す。
    def parse_sale_price(text)
      value = clean_text(text).tr("：", ":")
      return if value.empty?

      sale_part = value.include?("売買") ? value.split("売買", 2).last : value
      sale_part = sale_part.split(/賃貸|\//, 2).first
      amounts = sale_part.scan(/[\d,]+(?:\.\d+)?/).map { |amount| amount.delete(",").to_f }
      return if amounts.empty?

      (amounts.last * 10_000).to_i
    end

    # 値下げ表記や売買併記から、現在の月額賃料を円で返す。
    def parse_monthly_rent(text)
      value = clean_text(text).tr("：", ":")
      return if value.empty?

      rent_part = value.include?("賃貸") ? value.split("賃貸", 2).last : value
      rent_part = rent_part.split("売買", 2).first
      amounts = rent_part.scan(/[\d,]+(?:\.\d+)?/).map { |amount| amount.delete(",").to_f }
      return if amounts.empty?

      (amounts.last * 10_000).to_i
    end

    def list_layout(node)
      price_node = node.at_css(".searchPrice")
      return if price_node.nil?

      clone = price_node.dup
      clone.css("span").remove
      clean_text(clone.text)
    end

    def extract_area(text)
      clean_text(text).sub(/\A敷地面積\s*/, "").presence
    end

    # 詳細ページ内のリンク文言と、同一地域を区別する表示用丸数字を住所から除く。
    def normalize_address(address)
      clean_text(address).sub(/\s*[（(]GoogleMapで.*\z/, "").gsub(/[①-⑳]/, "").strip.presence
    end

    # NEW・交渉中は状態表示なので取り込まず、物件特性タグだけを保存する。
    def extract_taketa_tags(node)
      node.css(".searchTag a").map { |tag| clean_text(tag.text) }.reject(&:empty?).uniq
    end

    def update_images_from_list(listing, node)
      url = node.at_css(".photoBox img")&.[]("src")
      return if url.blank?

      image = listing.listing_images.find_or_initialize_by(remote_url: url)
      image.position ||= 1
      image.is_main = true if listing.listing_images.none?(&:is_main?)
      image.save!
    end

    def update_images_from_detail(listing, doc)
      main_url = doc.at_css(".searchListSub .slides img")&.[]("src")
      floor_plan_url = doc.at_css(".madoriBox a[href]")&.[]("href") || doc.at_css(".madoriBox img")&.[]("src")
      urls = [ main_url, floor_plan_url ].compact
      upsert_images(listing, urls, reset_main: true) if urls.any?
    end

    # 竹田市の画像は他サイトと分けて物件番号単位で保存する。
    def image_storage_path(listing, remote_url)
      uri = URI.parse(encode_non_ascii_url(remote_url))
      filename = File.basename(uri.path)
      File.join(IMAGE_STORAGE_ROOT, listing.external_id.to_s, filename)
    rescue URI::InvalidURIError
      super
    end

    def fetch_with_redirects(url, limit = 3)
      super(encode_non_ascii_url(url), limit)
    end

    def encode_non_ascii_url(url)
      url.to_s.gsub(/[^\x00-\x7F]/) do |character|
        character.bytes.map { |byte| format("%%%02X", byte) }.join
      end
    end

    def taketa_municipality
      @taketa_municipality ||= Municipality.find_by!(code: MUNICIPALITY_CODE)
    end

    def detail_path_for(external_id)
      File.join(@detail_dir, "taketa-iju-detail-#{external_id}.html")
    end
  end
end
