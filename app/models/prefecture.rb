# 都道府県マスタ。
class Prefecture < ApplicationRecord
  has_many :municipalities, dependent: :destroy
end
