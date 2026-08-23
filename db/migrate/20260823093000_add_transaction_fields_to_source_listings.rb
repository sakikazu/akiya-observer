class AddTransactionFieldsToSourceListings < ActiveRecord::Migration[7.2]
  def change
    add_column :source_listings, :transaction_type, :string, null: false, default: "sale"
    add_column :source_listings, :monthly_rent, :integer
    add_index :source_listings, :transaction_type
  end
end
