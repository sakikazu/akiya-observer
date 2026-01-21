class CreateMunicipalities < ActiveRecord::Migration[7.2]
  def change
    create_table :municipalities do |t|
      t.references :prefecture, null: false, foreign_key: true
      t.string :name, null: false
      t.string :name_kana
      t.string :code

      t.timestamps
    end
  end
end
