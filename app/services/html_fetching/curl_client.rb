require "open3"

module HtmlFetching
  # curl で HTML を取得する共通クライアント。
  class CurlClient
    DEFAULT_REFERER = "https://www.google.com/".freeze

    def initialize(user_agent:, timeout_seconds:, logger: nil, sleep_range: nil)
      @user_agent = user_agent
      @timeout_seconds = timeout_seconds
      @logger = logger
      @sleep_range = sleep_range
    end

    def fetch(url, referer: DEFAULT_REFERER)
      cmd = [
        "curl", "-L", "-sS", "--compressed",
        "--connect-timeout", @timeout_seconds.to_s,
        "--max-time", @timeout_seconds.to_s,
        "-H", "User-Agent: #{@user_agent}",
        "-H", "Accept: text/html,application/xhtml+xml",
        "-H", "Accept-Language: ja,en-US;q=0.9",
        "-H", "Accept-Encoding: gzip, deflate, br",
        "-H", "Sec-Fetch-Site: none",
        "-H", "Sec-Fetch-Mode: navigate",
        "-H", "Sec-Fetch-User: ?1",
        "-H", "Sec-Fetch-Dest: document",
        "-H", "Referer: #{referer.presence || DEFAULT_REFERER}",
        "-w", "\nHTTPSTATUS:%{http_code}",
        url
      ]

      stdout, stderr, status = Open3.capture3(*cmd)
      unless status.success?
        message = "curl failed (#{status.exitstatus}): #{stderr}"
        log(message)
        raise StandardError, message
      end

      marker = "\nHTTPSTATUS:".b
      stdout_bin = stdout.b
      html_bin, http_status = stdout_bin.split(marker, 2)
      if http_status.nil?
        message = "curl output missing HTTP status marker for #{url}"
        log(message)
        raise StandardError, message
      end

      code = http_status.to_i
      if code != 200
        message = "curl returned HTTP #{code} for #{url}"
        log(message)
        raise StandardError, message
      end

      sleep_random
      html_bin.force_encoding("UTF-8").scrub
    end

    private

    def log(message)
      @logger&.info(message)
    end

    def sleep_random
      return unless @sleep_range

      sleep(rand(@sleep_range))
    end
  end
end
