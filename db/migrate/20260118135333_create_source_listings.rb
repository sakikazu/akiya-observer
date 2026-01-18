class CreateSourceListings < ActiveRecord::Migration[7.2]
  def change
    create_table :source_listings do |t|
      t.references :source_site, null: false, foreign_key: true
      t.string :external_id
      t.text :url
      t.integer :status
      t.json :raw_payload
      t.datetime :first_seen_at
      t.datetime :last_seen_at
      t.datetime :disappeared_at
      t.datetime :last_checked_at

      t.timestamps
    end
  end
end
