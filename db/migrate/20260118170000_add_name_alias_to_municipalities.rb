class AddNameAliasToMunicipalities < ActiveRecord::Migration[7.2]
  def change
    add_column :municipalities, :name_alias, :string
  end
end
