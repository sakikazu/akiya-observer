# 市区町村マスタ。
class Municipality < ApplicationRecord
  belongs_to :prefecture
  has_many :source_listings, dependent: :destroy
  has_many :elementary_schools, dependent: :destroy

  # 正式名・別名のどちらかで一致する市区町村を返す。
  def self.find_by_name_or_alias(name)
    where(name: name).or(where(name_alias: name)).first
  end

  # テキスト内に含まれる市区町村名を検索して返す。
  def self.find_by_text_match(text, prefecture: nil)
    return if text.to_s.strip.empty?

    query = where("name IS NOT NULL OR name_alias IS NOT NULL").select(:id, :name, :name_alias)
    query = query.where(prefecture: prefecture) if prefecture

    target = text.to_s
    candidates = []
    query.find_each do |municipality|
      name = municipality.name.to_s
      alias_name = municipality.name_alias.to_s
      if !name.empty? && target.include?(name)
        candidates << [municipality, name.length]
      elsif !alias_name.empty? && target.include?(alias_name)
        candidates << [municipality, alias_name.length]
      end
    end

    candidates.max_by { |(_municipality, length)| length }&.first
  end
end
