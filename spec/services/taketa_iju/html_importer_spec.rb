require "rails_helper"

RSpec.describe TaketaIju::HtmlImporter do
  subject(:importer) { described_class.new(download_images: false) }

  let!(:prefecture) { Prefecture.create!(name: "大分県", code: "44") }
  let!(:municipality) { Municipality.create!(prefecture: prefecture, name: "竹田市", code: "442089") }

  let(:list_html) do
    <<~HTML
      <ul class="searchList">
        <li>
          <a href="/house/sale/"><p class="listNumber"><span>No.</span>490</p><div class="searchStatus nowTxt">交渉中</div><div class="photoBox"><img src="https://example.com/490.jpg"><span class="searchAdd">竹田</span></div></a>
          <div class="searchType color03">売買</div><div class="searchPrice">8DK<span><span>500→350</span>万円</span></div><p class="searchArea">敷地面積 317.35㎡</p><div class="searchTag"><a>農地付き物件</a></div>
        </li>
        <li>
          <a href="/house/rent/"><p class="listNumber"><span>No.</span>489</p></a><div class="searchType color02">賃貸</div><div class="searchPrice">4.5万円</div>
        </li>
        <li>
          <a href="/house/both/"><p class="listNumber"><span>No.</span>477</p><div class="photoBox"><span class="searchAdd">竹田</span></div></a>
          <div class="searchType twoLine color01">売買賃貸</div><div class="searchPrice">7DK<span><span>売買：780/賃貸：4.5</span>万円</span></div>
        </li>
      </ul>
    HTML
  end

  let(:detail_html) do
    <<~HTML
      <div class="searchTtlSub"><div class="searchType">売買</div><p class="ttl">竹田市大字飛田川</p></div>
      <div class="searchListSub"><div class="searchPrice">8DK<span><span>350</span>万円</span></div><ul class="slides"><li><img src="https://example.com/detail.jpg"></li></ul></div>
      <div class="madoriBox"><a href="https://example.com/floor-plan.jpg"><img src="https://example.com/floor-plan-small.jpg"></a></div>
      <div class="searchTag"><a>農地付き物件</a></div>
      <table class="table01">
        <tr><th>物件所在地</th><td>竹田市大字飛田川① (GoogleMapで見る)</td></tr>
        <tr><th>構造</th><td>木造瓦葺2階建</td></tr>
        <tr><th>間取り</th><td>8DK</td></tr>
        <tr><th>敷地面積</th><td>317.35㎡</td></tr>
        <tr><th>延床面積</th><td>145.54㎡</td></tr>
        <tr><th>建築時期</th><td>大正末期ごろ</td></tr>
        <tr><th>更新日</th><td>2026年07月29日</td></tr>
      </table>
    HTML
  end

  describe "物件の一覧取り込み" do
    it "売買・賃貸・併記を区別し、交渉中を無視して現在価格を保存する" do
      doc = Nokogiri::HTML(list_html)
      source_site = importer.send(:find_or_create_source_site)
      nodes = importer.send(:listing_nodes, doc)

      expect(nodes.size).to eq(3)
      sale = importer.send(:upsert_from_list, nodes.first, source_site)
      rent = importer.send(:upsert_from_list, nodes.second, source_site)
      both = importer.send(:upsert_from_list, nodes.third, source_site)

      expect(sale).to have_attributes(external_id: "490", transaction_type: "sale", price: 3_500_000, monthly_rent: nil, layout: "8DK", municipality: municipality)
      expect(sale.tag_list).to eq("農地付き物件")
      expect(sale.tag_list).not_to include("交渉中")
      expect(rent).to have_attributes(external_id: "489", transaction_type: "rent", price: nil, monthly_rent: 45_000)
      expect(both).to have_attributes(external_id: "477", transaction_type: "sale_and_rent", price: 7_800_000, monthly_rent: 45_000)
    end
  end

  describe "詳細取り込み" do
    it "公開住所、物件属性、更新日、画像URLを保存する" do
      source_site = importer.send(:find_or_create_source_site)
      node = importer.send(:listing_nodes, Nokogiri::HTML(list_html)).first
      listing = importer.send(:upsert_from_list, node, source_site)

      importer.send(:update_from_detail, listing, Nokogiri::HTML(detail_html))
      listing.reload

      expect(listing).to have_attributes(
        title: "竹田市大字飛田川",
        address: "竹田市大字飛田川",
        address_precision: "area",
        building_area: "145.54㎡",
        structure: "木造瓦葺2階建",
        built_year_month: "大正末期ごろ"
      )
      expect(listing.source_updated_at.to_date).to eq(Date.new(2026, 7, 29))
      expect(listing.listing_images.pluck(:remote_url)).to include("https://example.com/detail.jpg")
      expect(listing.listing_images.pluck(:remote_url)).to include("https://example.com/floor-plan.jpg")
    end
  end

  describe "画像URL" do
    it "日本語を含むURLの非ASCII部分をエンコードする" do
      encoded = importer.send(:encode_non_ascii_url, "https://example.com/画像-大.jpg")

      expect(encoded).to eq("https://example.com/%E7%94%BB%E5%83%8F-%E5%A4%A7.jpg")
    end
  end
end
