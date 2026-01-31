namespace :disappear do
  desc "Mark listings as disappeared based on daily crawl record"
  task mark: :environment do
    source_code = ENV.fetch("SOURCE_CODE", "ok-smile")

    source_site = SourceSite.find_by!(code: source_code)
    crawled_on = Date.current
    crawl = DailyCrawl.find_by(source_site: source_site, crawled_on: crawled_on)
    unless crawl
      puts "no daily_crawl record for crawled_on=#{crawled_on} source=#{source_code}"
      next
    end
    today_ids = Array(crawl.external_ids).map(&:to_s).uniq

    scope = SourceListing.where(source_site: source_site)
    active_listings = scope.where(disappeared_at: nil)
    now = Time.current

    disappeared_ids = active_listings.where.not(external_id: today_ids).pluck(:id)
    reappear_ids = scope.where(external_id: today_ids).where.not(disappeared_at: nil).pluck(:id)

    SourceListing.where(id: disappeared_ids).update_all(disappeared_at: now) if disappeared_ids.any?
    SourceListing.where(id: reappear_ids).update_all(disappeared_at: nil) if reappear_ids.any?

    puts "crawled_on=#{crawled_on} source=#{source_code} ids=#{today_ids.size} disappeared=#{disappeared_ids.size} reappeared=#{reappear_ids.size}"
  end
end
