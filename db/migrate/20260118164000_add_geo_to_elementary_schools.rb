class AddGeoToElementarySchools < ActiveRecord::Migration[7.2]
  def change
    add_column :elementary_schools, :latitude, :decimal, precision: 10, scale: 6
    add_column :elementary_schools, :longitude, :decimal, precision: 10, scale: 6
  end
end
