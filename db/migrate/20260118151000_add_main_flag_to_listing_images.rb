class AddMainFlagToListingImages < ActiveRecord::Migration[7.2]
  def change
    add_column :listing_images, :is_main, :boolean, null: false, default: false
    add_index :listing_images, :is_main
  end
end
