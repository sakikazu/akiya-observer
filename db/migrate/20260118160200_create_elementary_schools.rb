class CreateElementarySchools < ActiveRecord::Migration[7.2]
  def change
    create_table :elementary_schools do |t|
      t.references :municipality, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :total_students
      t.text :address
      t.text :memo
      t.integer :teachers_count

      t.timestamps
    end
  end
end
