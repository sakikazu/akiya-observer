class AddNameKanaToMunicipalities < ActiveRecord::Migration[7.2]
  def change
    add_column :municipalities, :name_kana, :string
  end
end
