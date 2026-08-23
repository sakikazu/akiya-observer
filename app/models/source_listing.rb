class SourceListing < ApplicationRecord
  TRANSACTION_TYPES = %w[sale rent sale_and_rent].freeze

  belongs_to :source_site
  belongs_to :municipality, optional: true

  has_many :favorites, dependent: :destroy
  has_many :listing_images, dependent: :destroy

  validates :transaction_type, inclusion: { in: TRANSACTION_TYPES }

  # サイトごとにポップアップで目立たせたい注目情報を文字列で返す。
  def highlight_text
    case source_site&.code
    when "cocosma-ina"
      value = detail_info["通学区"].to_s.strip
      return if value.blank?

      "通学区: #{value}"
    end
  end

  private

  def detail_info
    return {} unless extra_payload.is_a?(Hash)

    payload = extra_payload["detail_info"]
    payload.is_a?(Hash) ? payload : {}
  end
end
