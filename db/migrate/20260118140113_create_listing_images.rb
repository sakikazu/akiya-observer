class CreateListingImages < ActiveRecord::Migration[7.2]
  def change
    create_table :listing_images do |t|
      t.references :source_listing, null: false, foreign_key: true
      t.text :remote_url
      t.text :local_path
      t.integer :position
      t.datetime :downloaded_at
      t.string :checksum
      t.string :content_type
      t.integer :filesize
      t.integer :width
      t.integer :height

      t.timestamps
    end
  end
end
