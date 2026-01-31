class ReportsController < ApplicationController
  START_DATE = Date.new(2026, 1, 26)

  def municipality_weekly
    @weeks = build_weeks
    @prefecture = Prefecture.find_by!(code: "33")
    @municipalities = @prefecture.municipalities.order(:name)
    @weekly_counts = build_weekly_counts(@weeks)
  end

  private

  def build_weeks
    first_week_start = START_DATE.beginning_of_week(:monday)
    last_week_start = Date.current.beginning_of_week(:monday)
    weeks = []
    current = first_week_start
    while current <= last_week_start
      weeks << {
        key: current.to_s,
        start_date: current,
        end_date: current + 6
      }
      current += 7
    end
    weeks
  end

  def build_weekly_counts(weeks)
    weeks.each_with_object({}) do |week, hash|
      range = week[:start_date].beginning_of_day..week[:end_date].end_of_day
      end_time = week[:end_date].end_of_day
      disappeared_rows = SourceListing.where(disappeared_at: range)
        .where.not(first_seen_at: nil)
        .pluck(:municipality_id, :first_seen_at, :disappeared_at)
      avg_days = compute_avg_days(disappeared_rows)
      hash[week[:key]] = {
        new: SourceListing.where(first_seen_at: range).group(:municipality_id).count,
        disappeared: SourceListing.where(disappeared_at: range).group(:municipality_id).count,
        total: SourceListing.where("first_seen_at <= ?", end_time)
          .where("disappeared_at IS NULL OR disappeared_at > ?", end_time)
          .group(:municipality_id)
          .count,
        avg_days_to_disappear: avg_days
      }
    end
  end

  def compute_avg_days(rows)
    grouped = rows.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(municipality_id, first_seen_at, disappeared_at), acc|
      next if municipality_id.nil? || first_seen_at.nil? || disappeared_at.nil?

      days = ((disappeared_at - first_seen_at) / 1.day).to_f
      acc[municipality_id] << days if days >= 0
    end

    grouped.transform_values do |days|
      next nil if days.empty?

      (days.sum / days.size).round(1)
    end
  end
end
