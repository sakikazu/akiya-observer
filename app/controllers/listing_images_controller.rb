# DBに保存したローカル画像を安全に配信する。
class ListingImagesController < ApplicationController
  def show
    image = ListingImage.find(params[:id])
    return head :not_found if image.local_path.blank?

    path = Rails.root.join(image.local_path).cleanpath
    return head :forbidden unless path.to_s.start_with?(Rails.root.to_s)
    return head :not_found unless File.exist?(path)

    send_file path, type: image.content_type, disposition: "inline"
  end
end
