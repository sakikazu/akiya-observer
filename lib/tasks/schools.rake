namespace :schools do
  desc "Import elementary schools from Gaccom (URL required, MUNICIPALITY_ID optional)"
  task gaccom_import: :environment do
    url = ENV.fetch("URL")
    municipality = Municipality.find_by(id: ENV["MUNICIPALITY_ID"]) if ENV["MUNICIPALITY_ID"].present?

    Schools::GaccomImporter.new(url: url, municipality: municipality).call
  end
end
