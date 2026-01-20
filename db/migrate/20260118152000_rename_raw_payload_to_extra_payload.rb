class RenameRawPayloadToExtraPayload < ActiveRecord::Migration[7.2]
  def change
    rename_column :source_listings, :raw_payload, :extra_payload
  end
end
