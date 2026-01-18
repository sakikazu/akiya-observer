class CreateSourceSites < ActiveRecord::Migration[7.2]
  def change
    create_table :source_sites do |t|
      t.string :name
      t.string :code
      t.string :base_url
      t.string :search_url
      t.boolean :active

      t.timestamps
    end
    add_index :source_sites, :code
  end
end
