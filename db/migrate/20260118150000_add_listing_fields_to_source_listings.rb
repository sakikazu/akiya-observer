class AddListingFieldsToSourceListings < ActiveRecord::Migration[7.2]
  def change
    add_column :source_listings, :title, :string
    add_column :source_listings, :price, :integer
    add_column :source_listings, :tag_list, :string
    add_column :source_listings, :built_year_month, :string
    add_column :source_listings, :layout, :string
    add_column :source_listings, :land_area, :string
    add_column :source_listings, :building_area, :string
    add_column :source_listings, :structure, :string
    add_column :source_listings, :zoning, :string
    add_column :source_listings, :building_coverage_ratio, :string
    add_column :source_listings, :floor_area_ratio, :string
    add_column :source_listings, :source_updated_at, :datetime
  end
end
