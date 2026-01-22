require "logger"
require "open3"
require "nokogiri"
require "uri"

module Schools
  # Gaccomの市区町村ページから小学校一覧を取得して保存する。
  class GaccomImporter
    DEFAULT_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    def initialize(url:, municipality: nil, logger: nil)
      @url = url
      @municipality = municipality
      @logger = logger || Logger.new($stdout)
    end

    def call
      html = fetch_html(@url)
      doc = Nokogiri::HTML(html)
      municipality = resolve_municipality(doc)
      raise StandardError, "municipality not found" if municipality.nil?

      schools = parse_school_blocks(doc, html)
      log("found #{schools.size} schools")

      schools.each do |school|
        record = municipality.elementary_schools.find_or_initialize_by(name: school[:name])
        record.address = school[:address]
        record.total_students = school[:total_students]
        record.teachers_count = school[:teachers_count]
        record.memo = school[:memo]
        record.detail_url = school[:detail_url]
        record.latitude = school[:latitude]
        record.longitude = school[:longitude]
        record.save!
      end
    end

    private

    # curlで取得してSSLの互換性問題を回避する。
    def fetch_html(url)
      cmd = [
        "curl", "-L", "-sS",
        "--ciphers", "DEFAULT@SECLEVEL=1",
        "-H", "User-Agent: #{DEFAULT_USER_AGENT}",
        "-H", "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "-H", "Accept-Language: ja,en-US;q=0.9,en;q=0.8",
        "-w", "\nHTTPSTATUS:%{http_code}",
        url
      ]

      stdout, stderr, status = Open3.capture3(*cmd)
      unless status.success?
        raise StandardError, "curl failed (#{status.exitstatus}): #{stderr}"
      end

      html, http_status = stdout.split("\nHTTPSTATUS:")
      code = http_status.to_i
      raise StandardError, "failed to fetch #{url} (#{code})" unless code == 200

      html
    end

    def resolve_municipality(doc)
      return @municipality if @municipality

      title = doc.at_css("title")&.text.to_s
      description = doc.at_css("meta[name=\"description\"]")&.[]("content").to_s
      og_description = doc.at_css("meta[property=\"og:description\"]")&.[]("content").to_s
      text = [description, og_description, title].join(" ")

      pref_name = nil
      muni_name = nil

      if text =~ /(.+県)(.+?)(市|区|町|村)/
        pref_name = Regexp.last_match(1)
        muni_name = "#{Regexp.last_match(2)}#{Regexp.last_match(3)}"
      end

      if muni_name.nil? && title =~ /(.+?)の小学校/
        muni_name = Regexp.last_match(1)
      end

      muni_name = normalize_municipality_name(muni_name)
      prefecture = pref_name ? Prefecture.find_by(name: pref_name) : prefecture_from_url

      return Municipality.find_by(prefecture: prefecture, name: muni_name) if prefecture && muni_name
      return Municipality.find_by(name: muni_name) if muni_name

      nil
    end

    def parse_school_blocks(doc, html)
      coord_map = parse_marker_coordinates(html)
      schools = parse_school_blocks_from_dom(doc, coord_map)
      return schools if schools.any?

      parse_school_blocks_from_text(doc)
    end

    # DOM構造から学校情報を抜き出す。
    def parse_school_blocks_from_dom(doc, coord_map)
      schools = []
      doc.css("li.school_list_city .school_detail_data").each do |node|
        name = clean(node.at_css(".school_name span")&.text)
        url = node.at_css(".school_name a")&.[]("href") || node["data-url"]
        address = clean(node.at_css(".item.position .small")&.text)
        next if name.empty?

        coords = coord_map[url]
        schools << {
          name: name,
          address: address.presence,
          total_students: nil,
          teachers_count: nil,
          memo: nil,
          detail_url: url,
          latitude: coords&.fetch(:latitude, nil),
          longitude: coords&.fetch(:longitude, nil)
        }
      end
      schools.uniq { |school| school[:name] }
    end

    # フォールバックとしてテキスト抽出を使う。
    def parse_school_blocks_from_text(doc)
      lines = extract_school_section_lines(doc)
      schools = []
      index = 0
      while index < lines.size
        line = lines[index]
        if school_name_line?(line)
          name = clean(line)
          address = lines[(index + 1)..(index + 6)]&.find { |candidate| address_line?(candidate) }
          schools << {
            name: name,
            address: address.presence,
            total_students: nil,
            teachers_count: nil,
            memo: nil,
            detail_url: nil,
            latitude: nil,
            longitude: nil
          }
        end
        index += 1
      end
      schools.uniq { |school| school[:name] }
    end

    def extract_school_section_lines(doc)
      text = doc.text
      lines = text.split("\n").map { |line| clean(line) }.reject(&:empty?)

      start_index = lines.index { |line| line.include?("公立小学校一覧") }
      return lines unless start_index

      end_index = lines.index { |line| line.include?("小学校を地図で比較") } || lines.index { |line| line.include?("隣接市町村") }
      end_index ||= lines.size - 1

      lines[start_index..end_index]
    end

    def school_name_line?(line)
      return false unless line.include?("小学校")
      return false if line.include?("一覧")
      return false if line.include?("地図")

      true
    end

    def address_line?(line)
      return false if line.empty?

      line.match?(/(市|区|町|村).*[0-9０-９]/) || line.match?(/郡.*(町|村)/) || line.match?(/県.*(市|区|町|村)/)
    end

    def parse_marker_coordinates(html)
      coords = {}
      pattern = /L\.marker\(\s*\[([0-9.\-]+),\s*([0-9.\-]+)\][\s\S]*?bindPopup\('.*?<a href=\"([^\"]+)\">([^<]+)<\/a>/m
      html.scan(pattern).each do |lat, lng, url, _name|
        coords[url] = { latitude: lat.to_f, longitude: lng.to_f }
      end
      coords
    end

    def normalize_municipality_name(name)
      return if name.to_s.empty?

      name.to_s.gsub(/.+郡/, "").strip
    end

    def prefecture_from_url
      match = @url.match(/\/p(\d{2})\//)
      return if match.nil?

      Prefecture.find_by(code: match[1])
    end

    def clean(text)
      text.to_s.gsub(/\s+/, " ").strip
    end

    def log(message)
      @logger&.info(message)
    end
  end
end
