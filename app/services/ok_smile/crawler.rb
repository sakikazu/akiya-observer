require "open3"

module OkSmile
  # curl で取得した HTML を直接解析して DB に保存する（岡山県スコープ）。
  class Crawler < HtmlImporter
    DEFAULT_PAGE_THROTTLE_SECONDS = 0.0
    DEFAULT_PREFECTURE_CODE = "33"
    DEFAULT_PAGE_REQUEST_SLEEP_RANGE = (3.0..7.0)

    def initialize(search_url:, page_throttle_seconds: DEFAULT_PAGE_THROTTLE_SECONDS, fetch_detail: false, prefecture_code: DEFAULT_PREFECTURE_CODE, page_request_sleep_range: DEFAULT_PAGE_REQUEST_SLEEP_RANGE, fetch_all: false, start_page: 1, max_pages: nil, on_listing: nil, **kwargs)
      super(prefecture_code: prefecture_code, **kwargs)
      @search_url = search_url
      @page_throttle_seconds = page_throttle_seconds
      @fetch_detail = fetch_detail
      @fetch_all = fetch_all
      @page_request_sleep_range = (20.0..20.0)
      @start_page = start_page
      @max_pages = max_pages
      @on_listing = on_listing
    end

    def call
      source_site = find_or_create_source_site
      latest_known = SourceListing.where(source_site: source_site).maximum(:source_updated_at)
      log("latest known source_updated_at: #{latest_known || 'none'}")
      log("補足: 一覧HTMLの data-upd-time は物件の更新日時のUNIX秒。ページ内の最大値を使って巡回停止を判断します。")

      page = @start_page
      processed_pages = 0
      loop do
        url = search_url_for_page(page)
        log("request #{url}")
        html = fetch_html(url, referer: @base_url)
        doc = Nokogiri::HTML(html)
        nodes = doc.css("li.list-group-item[data-id]")
        break if nodes.empty?

        max_on_page = nil
        nodes.each do |node|
          list_updated_at = parse_unix_timestamp(node["data-upd-time"])
          max_on_page = [max_on_page, list_updated_at].compact.max

          listing = upsert_from_list(node, source_site)
          @on_listing&.call(listing)
          next if listing.url.blank? || !@fetch_detail

          log("request #{listing.url}")
          detail_html = fetch_html(listing.url, referer: @search_url)
          detail_doc = Nokogiri::HTML(detail_html)
          update_from_detail(listing, detail_doc)
        end

        if !@fetch_all && latest_known && max_on_page && max_on_page <= latest_known
          log("ページング停止: このページの最新更新(#{max_on_page})が既知の最新更新(#{latest_known})以下のため、以降は新規更新なしと判断")
          break
        end

        unless next_page_available?(doc, page + 1)
          log("stop paging: next page link not found")
          break
        end

        page += 1
        processed_pages += 1
        if @max_pages && processed_pages >= @max_pages
          if next_page_available?(doc, page)
            log("ページング停止: 指定したページ数(#{@max_pages})に到達。次のページは#{page}")
          else
            log("ページング停止: 指定したページ数(#{@max_pages})に到達、次ページなし")
          end
          break
        end
        sleep(@page_throttle_seconds) if @page_throttle_seconds.positive?
      end

      log("total requests: #{@request_count}")
    end

    private

    def search_url_for_page(page)
      uri = URI.parse(@search_url)
      params = URI.decode_www_form(uri.query.to_s)
      params.reject! { |key, _| key == "page" }
      params << ["page", page.to_s]
      uri.query = URI.encode_www_form(params)
      uri.to_s
    end

    def fetch_html(url, referer:)
      increment_request_count
      cmd = [
        "curl", "-L", "-sS", "--compressed",
        "--connect-timeout", REQUEST_TIMEOUT_SECONDS.to_s,
        "--max-time", REQUEST_TIMEOUT_SECONDS.to_s,
        "-H", "User-Agent: #{@user_agent}",
        "-H", "Accept: text/html,application/xhtml+xml",
        "-H", "Accept-Language: ja,en-US;q=0.9",
        "-H", "Accept-Encoding: gzip, deflate, br",
        "-H", "Sec-Fetch-Site: none",
        "-H", "Sec-Fetch-Mode: navigate",
        "-H", "Sec-Fetch-User: ?1",
        "-H", "Sec-Fetch-Dest: document",
        "-H", "Referer: https://www.google.com/",
        "-w", "\nHTTPSTATUS:%{http_code}",
        url
      ]

      stdout, stderr, status = Open3.capture3(*cmd)
      if status.success?
        html, http_status = stdout.split("\nHTTPSTATUS:")
        code = http_status.to_i
        if code == 200
          sleep(rand(@page_request_sleep_range))
          html
        else
          message = "curl returned HTTP #{code} for #{url}"
          log(message)
          raise StandardError, message
        end
      else
        message = "curl failed (#{status.exitstatus}): #{stderr}"
        log(message)
        raise StandardError, message
      end
    end

    def next_page_available?(doc, next_page)
      doc.css("a").any? do |link|
        href = link["href"].to_s
        href.include?("page=#{next_page}")
      end
    end
  end
end
