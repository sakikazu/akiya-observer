FactoryBot.define do
  factory :source_listing do
    source_site { nil }
    external_id { "MyString" }
    url { "MyText" }
    status { 1 }
    raw_payload { "" }
    first_seen_at { "2026-01-18 22:53:33" }
    last_seen_at { "2026-01-18 22:53:33" }
    disappeared_at { "2026-01-18 22:53:33" }
    last_checked_at { "2026-01-18 22:53:33" }
  end
end
