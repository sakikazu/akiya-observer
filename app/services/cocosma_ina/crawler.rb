require "nokogiri"
require "uri"

module CocosmaIna
  # ココスマ伊那の一覧を curl で巡回し、必要な詳細HTMLだけ保存して取り込む。
  class Crawler < HtmlImporter
    DEFAULT_PAGE_THROTTLE_SECONDS = 0.0
    DEFAULT_PAGE_REQUEST_SLEEP_RANGE = (1.0..3.0)

    def initialize(search_url:, page_throttle_seconds: DEFAULT_PAGE_THROTTLE_SECONDS, fetch_detail: true, page_request_sleep_range: DEFAULT_PAGE_REQUEST_SLEEP_RANGE, fetch_all: false, start_page: 1, max_pages: nil, on_listing: nil, **kwargs)
      super(**kwargs)
      @search_url = search_url
      @page_throttle_seconds = page_throttle_seconds
      @fetch_detail = fetch_detail
      @fetch_all = fetch_all
      @page_request_sleep_range = page_request_sleep_range
      @start_page = start_page
      @max_pages = max_pages
      @on_listing = on_listing
      @curl_client = HtmlFetching::CurlClient.new(
        user_agent: @user_agent,
        timeout_seconds: REQUEST_TIMEOUT_SECONDS,
        logger: @logger,
        sleep_range: @page_request_sleep_range
      )
    end

    def call
      source_site = find_or_create_source_site
      page = @start_page
      processed_pages = 0

      loop do
        url = search_url_for_page(page)
        log("request #{url}")
        html = fetch_html(url, referer: @base_url)
        doc = Nokogiri::HTML(html)
        nodes = list_nodes(doc)
        break if nodes.empty?

        nodes.each do |node|
          if pr_listing?(node)
            log("skip PR listing")
            next
          end

          list_updated_at = parse_list_updated_at(node)
          listing = upsert_from_list(node, source_site)
          @on_listing&.call(listing)
          next if listing.url.blank? || !@fetch_detail
          next unless should_fetch_detail?(listing, list_updated_at)

          log("request #{listing.url}")
          detail_html = fetch_html(listing.url, referer: @search_url)
          detail_doc = Nokogiri::HTML(detail_html)
          update_from_detail(listing, detail_doc)
        end

        next_url = next_page_url(doc)
        break if next_url.blank?

        page += 1
        processed_pages += 1
        if !@fetch_all && processed_pages >= @max_pages.to_i
          log("ページング停止: 指定したページ数(#{@max_pages})に到達")
          break
        end

        sleep(@page_throttle_seconds) if @page_throttle_seconds.positive?
      end

      log("total requests: #{@request_count}")
    end

    private

    def fetch_html(url, referer:)
      increment_request_count
      @curl_client.fetch(url, referer: referer)
    end

    def search_url_for_page(page)
      return @search_url if page == 1

      @search_url.sub(%r{/lists/(\d+)/\d+/q}) { "/lists/#{$1}/#{page}/q" }
    end

    def should_fetch_detail?(listing, list_updated_at)
      return true if listing.source_updated_at.nil?
      return false if list_updated_at.nil?

      list_updated_at > listing.source_updated_at
    end

    def next_page_url(doc)
      link = doc.at_css("ul.pagination a[aria-label='Next']") || doc.css("ul.pagination a").find do |anchor|
        anchor.text.to_s.include?("»")
      end
      href = link&.[]("href")
      return if href.blank?

      URI.join(@base_url, href).to_s
    rescue URI::InvalidURIError
      nil
    end
  end
end
