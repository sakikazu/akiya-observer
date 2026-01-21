namespace :municipalities do
  desc "Import municipalities from an XLS file (FILE required)"
  task import: :environment do
    path = ENV.fetch("FILE")
    Municipalities::XlsImporter.new(path: path).call
  end
end
