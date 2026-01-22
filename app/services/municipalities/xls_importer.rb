require "logger"

module Municipalities
  # 市区町村コードのExcelを読み込んで都道府県・市区町村マスタを更新する。
  class XlsImporter
    DEFAULT_SCAN_ROWS = 30

    def initialize(path:, logger: nil)
      @path = path
      @logger = logger || Logger.new($stdout)
    end

    def call
      sheet = Roo::Excel.new(@path).sheet(0)
      header_row = find_header_row(sheet)
      raise StandardError, "header row not found" if header_row.nil?

      headers = normalize_row(sheet.row(header_row))
      indices = header_indices(headers)
      raise StandardError, "required headers missing" if indices[:prefecture_name].nil?

      (header_row + 1).upto(sheet.last_row) do |row_number|
        row = sheet.row(row_number)
        next if row.compact.empty?

        pref_name = clean(row[indices[:prefecture_name]])
        muni_name = clean(row[indices[:municipality_name]]) if indices[:municipality_name]
        muni_kana = clean(row[indices[:municipality_kana]]) if indices[:municipality_kana]
        next if pref_name.empty?

        pref_code = indices[:prefecture_code] ? clean(row[indices[:prefecture_code]]) : nil
        muni_code = indices[:municipality_code] ? clean(row[indices[:municipality_code]]) : nil
        pref_code = derive_pref_code(pref_code, muni_code)

        prefecture = upsert_prefecture(pref_name, pref_code)
        next if muni_name.to_s.empty?

        upsert_municipality(prefecture, muni_name, muni_code, muni_kana)
      end
    end

    private

    def find_header_row(sheet)
      1.upto([sheet.last_row, DEFAULT_SCAN_ROWS].min) do |row_number|
        headers = normalize_row(sheet.row(row_number))
        next if headers.compact.empty?

        return row_number if header_indices(headers).values.compact.size >= 2
      end
      nil
    end

    def header_indices(headers)
      {
        prefecture_name: find_header_index(headers, ["都道府県", "都道府県名", "都道府県名称"]),
        municipality_name: find_header_index(headers, ["市区町村", "市区町村名", "市区町村名称"]),
        municipality_kana: find_header_index(headers, ["市区町村名 （カナ）", "市区町村名(カナ)", "市区町村名 カナ", "市区町村名 （ｶﾅ）", "市区町村名(ｶﾅ)"]),
        prefecture_code: find_header_index(headers, ["都道府県コード"]),
        municipality_code: find_header_index(headers, ["全国地方公共団体コード", "団体コード", "地方公共団体コード", "自治体コード"])
      }
    end

    def find_header_index(headers, candidates)
      headers.index do |header|
        candidates.any? { |candidate| header.include?(candidate) }
      end
    end

    def normalize_row(row)
      row.map { |value| clean(value) }
    end

    def clean(value)
      value.to_s.gsub(/\s+/, " ").strip
    end

    def derive_pref_code(pref_code, muni_code)
      return pref_code if pref_code.present?
      return if muni_code.blank?

      muni_code.gsub(/\D/, "")[0, 2]
    end

    def upsert_prefecture(name, code)
      prefecture = Prefecture.find_or_initialize_by(code: code.presence || name)
      prefecture.name = name
      prefecture.save!
      prefecture
    end

    def upsert_municipality(prefecture, name, code, name_kana)
      municipality = Municipality.find_or_initialize_by(prefecture: prefecture, code: code.presence || name)
      municipality.name = name
      municipality.name_kana = name_kana.presence || municipality.name_kana
      municipality.save!
    end
  end
end
