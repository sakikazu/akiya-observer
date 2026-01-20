class AddGeoFieldsToSourceListings < ActiveRecord::Migration[7.2]
  def change
    add_column :source_listings, :address, :text
    add_column :source_listings, :address_precision, :string
    add_column :source_listings, :latitude, :decimal, precision: 10, scale: 6
    add_column :source_listings, :longitude, :decimal, precision: 10, scale: 6
  end
end
