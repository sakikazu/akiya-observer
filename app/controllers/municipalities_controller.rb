# 市区町村の代表点を更新する。
class MunicipalitiesController < ApplicationController
  def representative_point
    municipality = Municipality.find(params[:id])
    latitude = params[:latitude]
    longitude = params[:longitude]
    if latitude.blank? || longitude.blank?
      render json: { error: "latitude/longitude required" }, status: :unprocessable_entity
      return
    end

    municipality.update!(
      representative_latitude: latitude,
      representative_longitude: longitude
    )

    render json: {
      id: municipality.id,
      representative_latitude: municipality.representative_latitude&.to_f,
      representative_longitude: municipality.representative_longitude&.to_f
    }
  end
end
