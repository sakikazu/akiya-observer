namespace :disappear do
  desc "Mark listings as disappeared based on daily crawl record"
  task mark: :environment do
    crawled_on = Date.current
    source_code = ENV["SOURCE_CODE"]&.strip

    source_sites =
      if source_code.present?
        [SourceSite.find_by!(code: source_code)]
      else
        DailyCrawl.includes(:source_site).where(crawled_on: crawled_on).map(&:source_site).compact.uniq
      end

    if source_sites.empty?
      puts "no daily_crawl records for crawled_on=#{crawled_on}"
      next
    end

    source_sites.each do |source_site|
      crawl = DailyCrawl.find_by(source_site: source_site, crawled_on: crawled_on)
      unless crawl
        puts "no daily_crawl record for crawled_on=#{crawled_on} source=#{source_site.code}"
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

      puts "crawled_on=#{crawled_on} source=#{source_site.code} ids=#{today_ids.size} disappeared=#{disappeared_ids.size} reappeared=#{reappear_ids.size}"
    end
  end
end
