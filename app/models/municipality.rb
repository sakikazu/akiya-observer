# 市区町村マスタ。
class Municipality < ApplicationRecord
  belongs_to :prefecture
  has_many :elementary_schools, dependent: :destroy
end
