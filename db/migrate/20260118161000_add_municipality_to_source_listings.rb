class AddMunicipalityToSourceListings < ActiveRecord::Migration[7.2]
  def change
    add_reference :source_listings, :municipality, foreign_key: true
  end
end
