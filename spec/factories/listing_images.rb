FactoryBot.define do
  factory :listing_image do
    source_listing { nil }
    remote_url { "MyText" }
    local_path { "MyText" }
    position { 1 }
    downloaded_at { "2026-01-18 23:01:13" }
    checksum { "MyString" }
    content_type { "MyString" }
    filesize { 1 }
    width { 1 }
    height { 1 }
  end
end
