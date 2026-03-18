import { Controller } from "@hotwired/stimulus"

const MISSING_MARKER_SIZE = 34
const RECENT_DAYS = 7

// 地図上に物件・小学校マーカーを描画し、距離表示を管理する。
export default class extends Controller {
  static targets = ["canvas", "count", "mode", "favorites", "municipalitySelect"]
  static values = { listings: Array, schools: Array, missing: Array, canFavorite: Boolean }

  // Leafletを初期化してレイヤーを用意する。
  connect() {
    if (!window.L) {
      console.warn("Leaflet is not loaded")
      return
    }

    this.includeDisappeared = false
    this.includeMissing = true
    this.includeRecentOnly = false
    this.representativeMode = false
    this.representativeTarget = null
    this.selectedMunicipalityId = this.initialMunicipalityId()
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
    this.missingLayer = window.L.layerGroup().addTo(this.map)

    this.handlePopupClick = this.handlePopupClick.bind(this)
    this.handleMapClick = this.handleMapClick.bind(this)
    this.handleFavoritesClick = this.handleFavoritesClick.bind(this)
    this.map.getContainer().addEventListener("click", this.handlePopupClick)
    this.map.on("click", this.handleMapClick)
    if (this.hasFavoritesTarget) {
      this.favoritesTarget.addEventListener("click", this.handleFavoritesClick)
    }
    this.renderMarkers()
    this.fitBounds()
    this.updateModeLabel()
  }

  disconnect() {
    if (this.map) {
      this.map.getContainer().removeEventListener("click", this.handlePopupClick)
      this.map.off("click", this.handleMapClick)
    }
    if (this.hasFavoritesTarget) {
      this.favoritesTarget.removeEventListener("click", this.handleFavoritesClick)
    }
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

  // 新着物件のみを表示する。
  toggleRecentOnly(event) {
    this.includeRecentOnly = event.target.checked
    this.renderMarkers()
    this.fitBounds()
  }

  // 市区町村の絞り込みを更新する。
  changeMunicipality(event) {
    const value = event.target.value
    const parsed = value ? Number(value) : null
    this.selectedMunicipalityId = Number.isNaN(parsed) ? null : parsed
    this.renderMarkers()
    this.fitBounds()
  }

  // 座標未取得の市区町村レイヤーの表示を切り替える。
  toggleMissing(event) {
    this.includeMissing = event.target.checked
    if (this.includeMissing) {
      this.map.addLayer(this.missingLayer)
    } else {
      this.map.removeLayer(this.missingLayer)
    }
    this.updateCount()
  }

  // 物件・小学校のマーカーを再描画する。
  renderMarkers() {
    this.activeLayer.clearLayers()
    this.disappearedLayer.clearLayers()
    this.schoolLayer.clearLayers()
    this.missingLayer.clearLayers()

    this.filteredListings().forEach((listing) => {
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

    this.filteredSchools().forEach((school) => {
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

    this.addMissingMarkers()

    if (!this.includeDisappeared) {
      this.map.removeLayer(this.disappearedLayer)
    }
    if (!this.includeMissing) {
      this.map.removeLayer(this.missingLayer)
    }
    this.updateCount()
  }

  // マーカーの範囲に合わせて地図の表示範囲を調整する。
  fitBounds() {
    const coords = this.filteredListings()
      .filter((listing) => listing.latitude && listing.longitude)
      .map((listing) => [listing.latitude, listing.longitude])

    if (this.includeMissing) {
      this.filteredMissing().forEach((missing) => {
        if (missing.latitude && missing.longitude) {
          coords.push([missing.latitude, missing.longitude])
        }
      })
    }

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
    const missingLabel = this.missingLabelText()
    if (this.includeDisappeared) {
      this.countTarget.textContent = `${activeCount + goneCount}件表示（終了${goneCount}件 / 小学校${schoolCount}件${missingLabel}）`
    } else {
      this.countTarget.textContent = `${activeCount}件表示（小学校${schoolCount}件${missingLabel}）`
    }
  }

  // 物件ポップアップのHTMLを生成する。
  popupHtml(listing, nearestSchool = null) {
    const resolvedNearest = nearestSchool || this.nearestSchool(listing)
    const precisionLabel = listing.address_precision === "block" ? "番地あり" : "番地なし"
    const image = listing.image_url
      ? `<img src="${listing.image_url}" alt="${listing.title}" class="popup-image">`
      : `<div class="popup-image placeholder"></div>`
    const price = listing.price || "価格未設定"
    const layout = listing.layout || "間取り不明"
    const address = listing.address || "住所未登録"
    const landArea = listing.land_area ? `土地面積: ${listing.land_area}` : "土地面積: 未登録"
    const buildingArea = listing.building_area ? `建物面積: ${listing.building_area}` : "建物面積: 未登録"
    const status = listing.disappeared_at ? "掲載終了" : "掲載中"
    const link = listing.url ? `<a href="${listing.url}" target="_blank" rel="noopener" class="popup-link">詳細を見る</a>` : ""
    const mapLink =
      listing.latitude && listing.longitude
        ? `<a href="https://www.google.com/maps?q=${listing.latitude},${listing.longitude}" target="_blank" rel="noopener" class="popup-link">Google Mapで見る</a>`
        : ""
    const linkGroup = [link, mapLink].filter(Boolean).join("")
    const firstSeenLine = this.metaLine("初回掲載日", listing.first_seen_at)
    const updatedLine = this.metaLine("更新日", listing.source_updated_at)
    const highlightLine = listing.highlight_text ? `<p class="popup-meta">${listing.highlight_text}</p>` : ""
    const linkGroupLine = linkGroup ? `<div class="popup-links">${linkGroup}</div>` : ""
    const favoriteButton = this.favoriteButtonHtml(listing)
    const distance = resolvedNearest
      ? `最寄り小学校まで ${resolvedNearest.distance_km.toFixed(2)}km（直線）`
      : "最寄り小学校: 未登録"

    return `
      <div class="popup-card">
        ${image}
        <div class="popup-body">
          <p class="popup-title">${listing.title || "物件名未登録"}</p>
          <p class="popup-meta">${price} / ${layout} / ${landArea} / ${buildingArea}</p>
          <p class="popup-meta">${address}</p>
          <div class="popup-row">
            <p class="popup-meta">${precisionLabel}</p>
            <p class="popup-meta">${status}</p>
          </div>
          <p class="popup-meta">${distance}</p>
          ${firstSeenLine}
          ${updatedLine}
          ${highlightLine}
          ${linkGroupLine}
          ${favoriteButton}
        </div>
      </div>
    `
  }

  // 未ジオコーディング市区町村のポップアップを生成する。
  missingPopupHtml(missing) {
    const name = missing.name || "市区町村不明"
    const count = missing.count || 0
    const listings = missing.listings || []
    const repStatus = missing.representative_set ? "代表点: 登録済み" : "代表点: 未設定"
    const actionButton = this.missingActionButton(missing)
    const items = this.missingListItems(missing, listings)
    const more = this.missingMoreLabel(missing)
    const note = this.missingRepresentativeNote(missing)
    return `
      <div class="popup-card">
        <div class="popup-body">
          <p class="popup-title">${name}</p>
          <p class="popup-meta">座標未取得: ${count}件</p>
          <p class="popup-meta">${repStatus}</p>
          ${actionButton}
          <div class="missing-list">
            ${items}
          </div>
          ${more}
          <p class="popup-meta">${note}</p>
        </div>
      </div>
    `
  }

  // 未ジオコーディングの件数バッジを生成する。
  missingIcon(count) {
    const size = MISSING_MARKER_SIZE
    return window.L.divIcon({
      html: `<span class="missing-marker__count">${count}</span>`,
      className: "missing-marker",
      iconSize: [size, size],
      iconAnchor: [size / 2, size / 2],
    })
  }

  // 最寄り小学校を計算して返す。
  nearestSchool(listing) {
    if (!listing.latitude || !listing.longitude) return null
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

  // 指定座標から最寄り小学校を計算して返す。
  nearestSchoolFromCoords(latitude, longitude, municipalityId) {
    if (!latitude || !longitude) return null
    if (!this.schoolsValue || this.schoolsValue.length === 0) return null

    const scoped = this.schoolsValue.filter((school) => {
      if (!school.latitude || !school.longitude) return false
      if (!municipalityId) return true
      return school.municipality_id === municipalityId
    })

    if (scoped.length === 0) return null

    let nearest = null
    scoped.forEach((school) => {
      const distance = this.haversineKm(latitude, longitude, school.latitude, school.longitude)
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

  totalMissingCount() {
    return this.filteredMissing().reduce((sum, missing) => sum + (missing.count || 0), 0)
  }

  filteredListings() {
    let listings = this.listingsValue
    listings = this.filteredByMunicipality(listings)
    if (!this.includeRecentOnly) return listings

    return listings.filter((listing) => this.isRecentListing(listing))
  }

  isRecentListing(listing) {
    if (!listing.first_seen_at) return false

    const start = new Date(listing.first_seen_at)
    const now = new Date()
    if (Number.isNaN(start.getTime())) return false

    const diffMs = now.getTime() - start.getTime()
    const diffDays = diffMs / (1000 * 60 * 60 * 24)
    return diffDays <= RECENT_DAYS
  }

  missingLabelText() {
    const missingCount = this.totalMissingCount()
    return this.includeMissing ? ` / 未取得${missingCount}件` : " / 未取得非表示"
  }

  addMissingMarkers() {
    this.filteredMissing().forEach((missing) => {
      if (!missing.latitude || !missing.longitude) return

      const marker = window.L.marker([missing.latitude, missing.longitude], {
        icon: this.missingIcon(missing.count || 0),
        className: "missing-marker-wrapper",
      })
      marker.bindPopup(this.missingPopupHtml(missing), { className: "listing-popup" })
      marker.addTo(this.missingLayer)
    })
  }

  // 絞り込み条件に合致する未取得市区町村のみ返す。
  filteredMissing() {
    if (!this.selectedMunicipalityId) return this.missingValue

    return this.missingValue.filter((missing) => missing.municipality_id === this.selectedMunicipalityId)
  }

  // 絞り込み条件に合致する小学校のみ返す。
  filteredSchools() {
    if (!this.selectedMunicipalityId) return this.schoolsValue

    return this.schoolsValue.filter((school) => school.municipality_id === this.selectedMunicipalityId)
  }

  // 絞り込み条件に合致する物件のみ返す。
  filteredByMunicipality(listings) {
    if (!this.selectedMunicipalityId) return listings

    return listings.filter((listing) => listing.municipality_id === this.selectedMunicipalityId)
  }

  missingActionButton(missing) {
    const actionLabel = this.representativeMode && this.representativeTarget?.municipality_id === missing.municipality_id
      ? "設定モード解除"
      : "代表点を設定"
    return `<button type="button" class="missing-list__action" data-missing-set-representative="1" data-missing-municipality-id="${missing.municipality_id}">
        ${actionLabel}
      </button>`
  }

  missingListItems(missing, listings) {
    const sorted = [...listings].sort((a, b) => this.listingFirstSeenTime(b) - this.listingFirstSeenTime(a))
    return sorted.map((listing) => {
      const title = this.truncateText(listing.title, 20, "物件名未登録")
      const firstSeen = listing.first_seen_at || "未登録"
      return `
        <button type="button" class="missing-list__item" data-missing-municipality-id="${missing.municipality_id}" data-missing-listing-id="${listing.id}">
          <span class="missing-list__title">${title}</span>
          <span class="missing-list__date">${firstSeen}</span>
        </button>
      `
    }).join("")
  }

  missingMoreLabel(missing) {
    if (!missing.remaining_count || missing.remaining_count <= 0) return ""

    return `<p class="popup-meta">他${missing.remaining_count}件</p>`
  }

  missingRepresentativeNote(missing) {
    return missing.representative_set
      ? "代表点（手動設定）"
      : "代表点（市区町村内の既知座標平均）"
  }

  // タイトル文字列を指定長で省略する。
  truncateText(text, limit, fallback) {
    const value = text || fallback
    const chars = Array.from(value)
    if (chars.length <= limit) return value
    return `${chars.slice(0, limit).join("")}…`
  }

  // 初回掲載日のソート用タイムスタンプを返す。
  listingFirstSeenTime(listing) {
    if (!listing.first_seen_at) return 0
    const time = new Date(listing.first_seen_at).getTime()
    return Number.isNaN(time) ? 0 : time
  }

  // メタ情報の表示行を生成する。
  metaLine(label, value) {
    if (!value) return ""
    return `<p class="popup-meta">${label}: ${value}</p>`
  }

  handlePopupClick(event) {
    const favoriteButton = event.target.closest("[data-favorite-toggle]")
    if (favoriteButton) {
      event.preventDefault()
      const listingId = Number(favoriteButton.dataset.favoriteListingId)
      const currentState = favoriteButton.dataset.favoriteState
      const isFavorite = currentState === "1" ? true : currentState === "0" ? false : null
      const listing = this.findListingById(listingId)
      if (listing) {
        this.toggleFavorite(listing, favoriteButton, isFavorite)
      }
      return
    }

    const setButton = event.target.closest("[data-missing-set-representative]")
    if (setButton) {
      event.preventDefault()
      const municipalityId = Number(setButton.dataset.missingMunicipalityId)
      const missing = this.findMissingEntry(municipalityId)
      if (missing) {
        if (this.representativeMode && this.representativeTarget?.municipality_id === municipalityId) {
          this.setRepresentativeMode(false)
        } else {
          this.setRepresentativeMode(true, missing)
        }
      }
      return
    }

    const button = event.target.closest("[data-missing-listing-id]")
    if (!button) return

    event.preventDefault()
    const municipalityId = Number(button.dataset.missingMunicipalityId)
    const listingId = Number(button.dataset.missingListingId)
    const missing = this.findMissingEntry(municipalityId)
    if (!missing) return

    const listing = (missing.listings || []).find((entry) => entry.id === listingId)
    if (!listing) return

    const nearest = this.nearestSchoolFromCoords(missing.latitude, missing.longitude, listing.municipality_id)
    const content = this.popupHtml(listing, nearest)
    window.L.popup({ className: "listing-popup", autoClose: false, closeOnClick: false })
      .setLatLng([missing.latitude, missing.longitude])
      .setContent(content)
      .addTo(this.map)
  }

  findMissingEntry(municipalityId) {
    return this.missingValue.find((entry) => entry.municipality_id === municipalityId)
  }

  favoriteButtonHtml(listing) {
    if (!this.canFavoriteValue) return ""

    const label = listing.favorite ? "お気に入り解除" : "お気に入り"
    const stateClass = listing.favorite ? " is-active" : ""
    const stateValue = listing.favorite ? "1" : "0"
    return `<button type="button" class="favorite-button${stateClass}" data-favorite-toggle="1" data-favorite-listing-id="${listing.id}" data-favorite-state="${stateValue}">
        ${label}
      </button>`
  }

  async toggleFavorite(listing, button, buttonState = null) {
    const token = document.querySelector("meta[name=\"csrf-token\"]")?.getAttribute("content")
    if (!token) {
      console.warn("CSRF token missing")
      return
    }

    const currentFavorite = buttonState === null ? listing.favorite : buttonState
    const nextFavorite = !currentFavorite
    const method = nextFavorite ? "POST" : "DELETE"
    try {
      const response = await fetch(`/favorites/${listing.id}`, {
        method,
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": token,
        },
      })

      if (!response.ok) {
        throw new Error(`favorite update failed (${response.status})`)
      }

      this.setFavoriteState(listing.id, nextFavorite)
      this.updateFavoriteButton(button, nextFavorite)
    } catch (error) {
      console.warn(error)
    }
  }

  updateFavoriteButton(button, isFavorite) {
    button.textContent = isFavorite ? "お気に入り解除" : "お気に入り"
    button.classList.toggle("is-active", isFavorite)
    button.dataset.favoriteState = isFavorite ? "1" : "0"
  }

  setFavoriteState(listingId, isFavorite) {
    this.eachListing((listing) => {
      if (listing.id === listingId) {
        listing.favorite = isFavorite
      }
    })
  }

  findListingById(listingId) {
    let found = null
    this.eachListing((listing) => {
      if (!found && listing.id === listingId) {
        found = listing
      }
    })
    return found
  }

  eachListing(callback) {
    this.listingsValue.forEach(callback)
    this.missingValue.forEach((missing) => {
      (missing.listings || []).forEach(callback)
    })
  }

  handleMapClick(event) {
    if (!this.representativeMode || !this.representativeTarget) return

    const { lat, lng } = event.latlng
    this.saveRepresentativePoint(this.representativeTarget, lat, lng)
  }

  handleFavoritesClick(event) {
    const item = event.target.closest("[data-favorite-listing-id]")
    if (!item) return

    const listingId = Number(item.dataset.favoriteListingId)
    const latitude = Number(item.dataset.favoriteLatitude)
    const longitude = Number(item.dataset.favoriteLongitude)
    if (!listingId) return

    const listing = this.findListingById(listingId)
    if (!listing) return

    if (Number.isFinite(latitude) && Number.isFinite(longitude) && latitude && longitude) {
      this.map.setView([latitude, longitude], 14)
      window.L.popup({ className: "listing-popup", autoClose: false, closeOnClick: false })
        .setLatLng([latitude, longitude])
        .setContent(this.popupHtml(listing))
        .addTo(this.map)
      return
    }

    const missingEntry = this.missingValue.find((entry) => (entry.listings || []).some((itemListing) => itemListing.id === listingId))
    if (!missingEntry) return

    this.map.setView([missingEntry.latitude, missingEntry.longitude], 12)
    window.L.popup({ className: "listing-popup", autoClose: false, closeOnClick: false })
      .setLatLng([missingEntry.latitude, missingEntry.longitude])
      .setContent(this.popupHtml(listing, this.nearestSchoolFromCoords(missingEntry.latitude, missingEntry.longitude, listing.municipality_id)))
      .addTo(this.map)
  }

  setRepresentativeMode(enabled, target = null) {
    this.representativeMode = enabled
    this.representativeTarget = enabled ? target : null
    this.updateModeLabel()
  }

  updateModeLabel() {
    if (!this.hasModeTarget) return

    if (this.representativeMode && this.representativeTarget) {
      this.modeTarget.textContent = `${this.representativeTarget.name}の代表点をクリックで設定`
      this.canvasTarget.classList.add("is-placing")
    } else {
      this.modeTarget.textContent = ""
      this.canvasTarget.classList.remove("is-placing")
    }
  }

  initialMunicipalityId() {
    if (!this.hasMunicipalitySelectTarget) return null

    const value = this.municipalitySelectTarget.value
    const parsed = value ? Number(value) : null
    return Number.isNaN(parsed) ? null : parsed
  }

  async saveRepresentativePoint(missing, latitude, longitude) {
    const token = document.querySelector("meta[name=\"csrf-token\"]")?.getAttribute("content")
    if (!token) {
      console.warn("CSRF token missing")
      return
    }

    try {
      const response = await fetch(`/municipalities/${missing.municipality_id}/representative_point`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": token,
        },
        body: JSON.stringify({ latitude, longitude }),
      })

      if (!response.ok) {
        throw new Error(`failed to update representative point (${response.status})`)
      }

      const payload = await response.json()
      missing.latitude = payload.representative_latitude
      missing.longitude = payload.representative_longitude
      missing.representative_set = true
      this.setRepresentativeMode(false)
      this.renderMarkers()
    } catch (error) {
      console.warn(error)
      this.setRepresentativeMode(false)
    }
  }
}
