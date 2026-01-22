class AddDetailUrlToElementarySchools < ActiveRecord::Migration[7.2]
  def change
    add_column :elementary_schools, :detail_url, :text
  end
end
