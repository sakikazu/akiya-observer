class AddRepresentativePointToMunicipalities < ActiveRecord::Migration[7.2]
  def change
    add_column :municipalities, :representative_latitude, :decimal, precision: 10, scale: 6
    add_column :municipalities, :representative_longitude, :decimal, precision: 10, scale: 6
  end
end
