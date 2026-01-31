# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_01_31_120000) do
  create_table "daily_crawls", force: :cascade do |t|
    t.date "crawled_on", null: false
    t.integer "source_site_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.integer "listing_count", default: 0, null: false
    t.json "external_ids", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["source_site_id", "crawled_on"], name: "index_daily_crawls_on_source_site_id_and_crawled_on", unique: true
    t.index ["source_site_id"], name: "index_daily_crawls_on_source_site_id"
  end

  create_table "elementary_schools", force: :cascade do |t|
    t.integer "municipality_id", null: false
    t.string "name", null: false
    t.integer "total_students"
    t.text "address"
    t.text "memo"
    t.integer "teachers_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.text "detail_url"
    t.index ["municipality_id"], name: "index_elementary_schools_on_municipality_id"
  end

  create_table "favorites", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "source_listing_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["source_listing_id"], name: "index_favorites_on_source_listing_id"
    t.index ["user_id", "source_listing_id"], name: "index_favorites_on_user_id_and_source_listing_id", unique: true
    t.index ["user_id"], name: "index_favorites_on_user_id"
  end

  create_table "listing_images", force: :cascade do |t|
    t.integer "source_listing_id", null: false
    t.text "remote_url"
    t.text "local_path"
    t.integer "position"
    t.datetime "downloaded_at"
    t.string "checksum"
    t.string "content_type"
    t.integer "filesize"
    t.integer "width"
    t.integer "height"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "is_main", default: false, null: false
    t.index ["is_main"], name: "index_listing_images_on_is_main"
    t.index ["source_listing_id"], name: "index_listing_images_on_source_listing_id"
  end

  create_table "municipalities", force: :cascade do |t|
    t.integer "prefecture_id", null: false
    t.string "name", null: false
    t.string "code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name_kana"
    t.string "name_alias"
    t.decimal "representative_latitude", precision: 10, scale: 6
    t.decimal "representative_longitude", precision: 10, scale: 6
    t.index ["prefecture_id"], name: "index_municipalities_on_prefecture_id"
  end

  create_table "prefectures", force: :cascade do |t|
    t.string "name", null: false
    t.string "code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "source_listings", force: :cascade do |t|
    t.integer "source_site_id", null: false
    t.string "external_id"
    t.text "url"
    t.integer "status"
    t.json "extra_payload"
    t.datetime "first_seen_at"
    t.datetime "last_seen_at"
    t.datetime "disappeared_at"
    t.datetime "last_checked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "title"
    t.integer "price"
    t.string "tag_list"
    t.string "built_year_month"
    t.string "layout"
    t.string "land_area"
    t.string "building_area"
    t.string "structure"
    t.string "zoning"
    t.string "building_coverage_ratio"
    t.string "floor_area_ratio"
    t.datetime "source_updated_at"
    t.text "address"
    t.string "address_precision"
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.integer "municipality_id"
    t.index ["municipality_id"], name: "index_source_listings_on_municipality_id"
    t.index ["source_site_id"], name: "index_source_listings_on_source_site_id"
  end

  create_table "source_sites", force: :cascade do |t|
    t.string "name"
    t.string "code"
    t.string "base_url"
    t.string "search_url"
    t.boolean "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_source_sites_on_code"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "daily_crawls", "source_sites"
  add_foreign_key "elementary_schools", "municipalities"
  add_foreign_key "favorites", "source_listings"
  add_foreign_key "favorites", "users"
  add_foreign_key "listing_images", "source_listings"
  add_foreign_key "municipalities", "prefectures"
  add_foreign_key "source_listings", "municipalities"
  add_foreign_key "source_listings", "source_sites"
end
