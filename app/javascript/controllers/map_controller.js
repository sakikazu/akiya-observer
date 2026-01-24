import { Controller } from "@hotwired/stimulus"

// 地図上に物件・小学校マーカーを描画し、距離表示を管理する。
export default class extends Controller {
  static targets = ["canvas", "count"]
  static values = { listings: Array, schools: Array }

  // Leafletを初期化してレイヤーを用意する。
  connect() {
    if (!window.L) {
      console.warn("Leaflet is not loaded")
      return
    }

    this.includeDisappeared = false
    this.map = window.L.map(this.canvasTarget, {
      zoomControl: false,
      minZoom: 5,
    })
    window.L.control.zoom({ position: "bottomright" }).addTo(this.map)

    window.L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: "&copy; OpenStreetMap contributors",
    }).addTo(this.map)

    this.activeLayer = window.L.layerGroup().addTo(this.map)
    this.disappearedLayer = window.L.layerGroup().addTo(this.map)
    this.schoolLayer = window.L.layerGroup().addTo(this.map)
    this.lineLayer = window.L.layerGroup().addTo(this.map)

    this.renderMarkers()
    this.fitBounds()
  }

  // 掲載終了物件のレイヤー表示を切り替える。
  toggleDisappeared(event) {
    this.includeDisappeared = event.target.checked
    if (this.includeDisappeared) {
      this.map.addLayer(this.disappearedLayer)
    } else {
      this.map.removeLayer(this.disappearedLayer)
    }
    this.updateCount()
  }

  // 小学校レイヤーの表示を切り替える。
  toggleSchools(event) {
    const show = event.target.checked
    if (show) {
      this.map.addLayer(this.schoolLayer)
    } else {
      this.map.removeLayer(this.schoolLayer)
    }
    this.updateCount()
  }

  // 物件・小学校のマーカーを再描画する。
  renderMarkers() {
    this.activeLayer.clearLayers()
    this.disappearedLayer.clearLayers()
    this.schoolLayer.clearLayers()

    this.listingsValue.forEach((listing) => {
      if (!listing.latitude || !listing.longitude) return

      const isDisappeared = Boolean(listing.disappeared_at)
      const precision = listing.address_precision === "block" ? "precise" : "area"
      const markerColor = isDisappeared ? "#9ca3af" : precision === "precise" ? "#f97316" : "#0ea5e9"
      const nearest = this.nearestSchool(listing)
      const marker = window.L.circleMarker([listing.latitude, listing.longitude], {
        radius: isDisappeared ? 8 : 10,
        color: markerColor,
        fillColor: markerColor,
        fillOpacity: isDisappeared ? 0.45 : 0.9,
        weight: isDisappeared ? 2 : 3,
        className: isDisappeared ? "listing-marker is-gone" : "listing-marker",
      })

      marker.bindPopup(this.popupHtml(listing, nearest), { className: "listing-popup" })
      marker.on("click", () => {
        if (nearest) {
          this.drawLine(listing, nearest)
        }
      })

      if (isDisappeared) {
        marker.addTo(this.disappearedLayer)
      } else {
        marker.addTo(this.activeLayer)
      }
    })

    this.schoolsValue.forEach((school) => {
      if (!school.latitude || !school.longitude) return

      const marker = window.L.circleMarker([school.latitude, school.longitude], {
        radius: 9,
        color: "#16a34a",
        fillColor: "#22c55e",
        fillOpacity: 0.95,
        weight: 3,
        className: "school-marker",
      })
      marker.bindPopup(this.schoolPopupHtml(school), { className: "listing-popup" })
      marker.addTo(this.schoolLayer)
    })

    if (!this.includeDisappeared) {
      this.map.removeLayer(this.disappearedLayer)
    }
    this.updateCount()
  }

  // マーカーの範囲に合わせて地図の表示範囲を調整する。
  fitBounds() {
    const coords = this.listingsValue
      .filter((listing) => listing.latitude && listing.longitude)
      .map((listing) => [listing.latitude, listing.longitude])

    if (coords.length === 0) {
      this.map.setView([34.6618, 133.9344], 9)
      return
    }

    const bounds = window.L.latLngBounds(coords)
    this.map.fitBounds(bounds, { padding: [40, 40] })
  }

  // 画面右上の件数表示を更新する。
  updateCount() {
    const activeCount = this.activeLayer.getLayers().length
    const goneCount = this.disappearedLayer.getLayers().length
    const schoolCount = this.schoolLayer.getLayers().length
    if (this.includeDisappeared) {
      this.countTarget.textContent = `${activeCount + goneCount}件表示（終了${goneCount}件 / 小学校${schoolCount}件）`
    } else {
      this.countTarget.textContent = `${activeCount}件表示（小学校${schoolCount}件）`
    }
  }

  // 物件ポップアップのHTMLを生成する。
  popupHtml(listing, nearestSchool) {
    const precisionLabel = listing.address_precision === "block" ? "番地あり" : "番地なし"
    const image = listing.image_url
      ? `<img src="${listing.image_url}" alt="${listing.title}" class="popup-image">`
      : `<div class="popup-image placeholder"></div>`
    const price = listing.price || "価格未設定"
    const layout = listing.layout || "間取り不明"
    const address = listing.address || "住所未登録"
    const landArea = listing.land_area ? `土地面積: ${listing.land_area}` : "土地面積: 未登録"
    const buildingArea = listing.building_area ? `建物面積: ${listing.building_area}` : "建物面積: 未登録"
    const updated = listing.source_updated_at ? `更新日: ${listing.source_updated_at}` : ""
    const status = listing.disappeared_at ? "掲載終了" : "掲載中"
    const link = listing.url ? `<a href="${listing.url}" target="_blank" rel="noopener">詳細を見る</a>` : ""
    const mapLink =
      listing.latitude && listing.longitude
        ? `<a href="https://www.google.com/maps?q=${listing.latitude},${listing.longitude}" target="_blank" rel="noopener">Google Mapで見る</a>`
        : ""
    const distance = nearestSchool
      ? `最寄り小学校まで ${nearestSchool.distance_km.toFixed(2)}km（直線）`
      : "最寄り小学校: 未登録"

    return `
      <div class="popup-card">
        ${image}
        <div class="popup-body">
          <p class="popup-title">${listing.title || "物件名未登録"}</p>
          <p class="popup-meta">${price} / ${layout}</p>
          <p class="popup-meta">${address}</p>
          <p class="popup-meta">${landArea}</p>
          <p class="popup-meta">${buildingArea}</p>
          <p class="popup-meta">${precisionLabel}・${status}</p>
          <p class="popup-meta">${distance}</p>
          <p class="popup-meta">${updated}</p>
          ${link}
          ${mapLink}
        </div>
      </div>
    `
  }

  // 最寄り小学校を計算して返す。
  nearestSchool(listing) {
    if (!this.schoolsValue || this.schoolsValue.length === 0) return null

    const scoped = this.schoolsValue.filter((school) => {
      if (!school.latitude || !school.longitude) return false
      if (!listing.municipality_id) return true
      return school.municipality_id === listing.municipality_id
    })

    if (scoped.length === 0) return null

    let nearest = null
    scoped.forEach((school) => {
      const distance = this.haversineKm(
        listing.latitude,
        listing.longitude,
        school.latitude,
        school.longitude
      )
      if (!nearest || distance < nearest.distance_km) {
        nearest = { ...school, distance_km: distance }
      }
    })
    return nearest
  }

  // 物件と最寄り小学校の直線を描画する。
  drawLine(listing, school) {
    this.lineLayer.clearLayers()
    const line = window.L.polyline(
      [
        [listing.latitude, listing.longitude],
        [school.latitude, school.longitude],
      ],
      {
        color: "#22c55e",
        weight: 2,
        opacity: 0.7,
        dashArray: "6 6",
      }
    )
    line.addTo(this.lineLayer)
  }

  // 緯度経度から直線距離(km)を計算する。
  haversineKm(lat1, lon1, lat2, lon2) {
    const toRad = (deg) => (deg * Math.PI) / 180
    const earthRadiusKm = 6371
    const dLat = toRad(lat2 - lat1)
    const dLon = toRad(lon2 - lon1)
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2)
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    return earthRadiusKm * c
  }

  // 小学校ポップアップのHTMLを生成する。
  schoolPopupHtml(school) {
    const address = school.address || "住所未登録"
    const memo = school.memo ? `<p class="popup-meta">${school.memo}</p>` : ""
    const link = school.detail_url
      ? `<a href="${school.detail_url}" target="_blank" rel="noopener">詳細を見る</a>`
      : ""
    const students = school.total_students ? `児童数: ${school.total_students}人` : "児童数: 未登録"
    const teachers = school.teachers_count ? `教員数: ${school.teachers_count}人` : "教員数: 未登録"

    return `
      <div class="popup-card">
        <div class="popup-body">
          <p class="popup-title">${school.name}</p>
          <p class="popup-meta">${address}</p>
          <p class="popup-meta">${students}</p>
          <p class="popup-meta">${teachers}</p>
          ${memo}
          ${link}
        </div>
      </div>
    `
  }
}
