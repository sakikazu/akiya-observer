import { Controller } from "@hotwired/stimulus"

// 地図上に物件マーカーを描画し、フィルタとポップアップを管理する。
export default class extends Controller {
  static targets = ["canvas", "count"]
  static values = { listings: Array, schools: Array }

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

    this.renderMarkers()
    this.fitBounds()
  }

  toggleDisappeared(event) {
    this.includeDisappeared = event.target.checked
    if (this.includeDisappeared) {
      this.map.addLayer(this.disappearedLayer)
    } else {
      this.map.removeLayer(this.disappearedLayer)
    }
    this.updateCount()
  }

  toggleSchools(event) {
    const show = event.target.checked
    if (show) {
      this.map.addLayer(this.schoolLayer)
    } else {
      this.map.removeLayer(this.schoolLayer)
    }
    this.updateCount()
  }

  renderMarkers() {
    this.activeLayer.clearLayers()
    this.disappearedLayer.clearLayers()
    this.schoolLayer.clearLayers()

    this.listingsValue.forEach((listing) => {
      if (!listing.latitude || !listing.longitude) return

      const isDisappeared = Boolean(listing.disappeared_at)
      const precision = listing.address_precision === "block" ? "precise" : "area"
      const marker = window.L.circleMarker([listing.latitude, listing.longitude], {
        radius: isDisappeared ? 6 : 7,
        color: isDisappeared ? "#8f95a3" : precision === "precise" ? "#f97316" : "#38bdf8",
        fillColor: isDisappeared ? "#8f95a3" : precision === "precise" ? "#f97316" : "#38bdf8",
        fillOpacity: isDisappeared ? 0.4 : 0.75,
        weight: 2,
      })

      marker.bindPopup(this.popupHtml(listing), { className: "listing-popup" })

      if (isDisappeared) {
        marker.addTo(this.disappearedLayer)
      } else {
        marker.addTo(this.activeLayer)
      }
    })

    this.schoolsValue.forEach((school) => {
      if (!school.latitude || !school.longitude) return

      const marker = window.L.circleMarker([school.latitude, school.longitude], {
        radius: 6,
        color: "#22c55e",
        fillColor: "#22c55e",
        fillOpacity: 0.8,
        weight: 2,
      })
      marker.bindPopup(this.schoolPopupHtml(school), { className: "listing-popup" })
      marker.addTo(this.schoolLayer)
    })

    if (!this.includeDisappeared) {
      this.map.removeLayer(this.disappearedLayer)
    }
    this.updateCount()
  }

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

  popupHtml(listing) {
    const precisionLabel = listing.address_precision === "block" ? "番地あり" : "番地なし"
    const image = listing.image_url
      ? `<img src="${listing.image_url}" alt="${listing.title}" class="popup-image">`
      : `<div class="popup-image placeholder"></div>`
    const price = listing.price || "価格未設定"
    const layout = listing.layout || "間取り不明"
    const address = listing.address || "住所未登録"
    const updated = listing.source_updated_at ? `更新日: ${listing.source_updated_at}` : ""
    const status = listing.disappeared_at ? "掲載終了" : "掲載中"
    const link = listing.url ? `<a href="${listing.url}" target="_blank" rel="noopener">詳細を見る</a>` : ""

    return `
      <div class="popup-card">
        ${image}
        <div class="popup-body">
          <p class="popup-title">${listing.title || "物件名未登録"}</p>
          <p class="popup-meta">${price} / ${layout}</p>
          <p class="popup-meta">${address}</p>
          <p class="popup-meta">${precisionLabel}・${status}</p>
          <p class="popup-meta">${updated}</p>
          ${link}
        </div>
      </div>
    `
  }

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
