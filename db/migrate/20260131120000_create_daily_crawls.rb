class CreateDailyCrawls < ActiveRecord::Migration[7.2]
  def change
    create_table :daily_crawls do |t|
      t.date :crawled_on, null: false
      t.references :source_site, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :listing_count, null: false, default: 0
      t.json :external_ids, null: false, default: []

      t.timestamps
    end

    add_index :daily_crawls, [:source_site_id, :crawled_on], unique: true
  end
end
