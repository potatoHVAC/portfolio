require "json"

class MediaCatalog
  class Error < StandardError; end
  class InvalidManifest < Error; end
  class InvalidAssetId < Error; end
  class UnknownAsset < Error; end
  class KindMismatch < Error; end

  VERSION = 1
  ASSET_ID = /\A[a-z0-9]+(?:-[a-z0-9]+)*(?:\/[a-z0-9]+(?:-[a-z0-9]+)*)*\z/
  SHA256 = "[0-9a-f]{64}"
  KINDS = %w[image video].freeze
  IMAGE_FORMATS = {
    "avif" => [ "image/avif", "avif" ],
    "webp" => [ "image/webp", "webp" ],
    "jpeg" => [ "image/jpeg", "jpg" ]
  }.freeze

  attr_reader :assets

  def initialize(path: Rails.root.join("config/media.json"), manifest: nil)
    data = manifest || JSON.parse(File.read(path))
    @assets = deep_freeze(validate_manifest!(deep_copy(data)))
  rescue JSON::ParserError, Errno::ENOENT => error
    raise InvalidManifest, "Could not load media manifest: #{error.message}"
  end

  def fetch!(id, kind: nil)
    validate_asset_id!(id)
    asset = assets[id] || raise(UnknownAsset, "Unknown media asset: #{id}")
    expected_kind = kind&.to_s
    if expected_kind && !KINDS.include?(expected_kind)
      raise ArgumentError, "Unsupported media kind: #{expected_kind}"
    end
    if expected_kind && asset.fetch("kind") != expected_kind
      raise KindMismatch, "Media asset #{id} is #{asset.fetch("kind")}, not #{expected_kind}"
    end

    asset
  end

  private

  def validate_manifest!(manifest)
    object!(manifest, "manifest")
    exact_keys!(manifest, %w[version assets], required: %w[version assets], label: "manifest")
    raise InvalidManifest, "Unsupported media manifest version: #{manifest["version"].inspect}" unless manifest["version"] == VERSION

    manifest_assets = object!(manifest["assets"], "manifest assets")
    manifest_assets.each_with_object({}) do |(id, asset), validated|
      validate_asset_id!(id)
      validated[id] = validate_asset!(id, object!(asset, "asset #{id}"))
    rescue InvalidAssetId => error
      raise InvalidManifest, error.message
    end
  end

  def validate_asset!(id, asset)
    case asset["kind"]
    when "image" then validate_image!(id, asset)
    when "video" then validate_video!(id, asset)
    else raise InvalidManifest, "Asset #{id} has an unsupported kind"
    end
    deep_freeze(asset)
  end

  def validate_image!(id, asset)
    exact_keys!(asset, %w[kind sourceSha256 alt decorative width height placeholder sources],
      required: %w[kind sourceSha256 alt width height placeholder sources], label: "image #{id}")
    sha256!(asset["sourceSha256"], "image #{id} source checksum")
    string!(asset["alt"], "image #{id} alt text")
    positive_integer!(asset["width"], "image #{id} width")
    positive_integer!(asset["height"], "image #{id} height")
    unless asset["placeholder"].is_a?(String) && asset["placeholder"].match?(%r{\Adata:image/jpeg;base64,[A-Za-z0-9+/]+={0,2}\z})
      raise InvalidManifest, "Image #{id} has an invalid placeholder"
    end
    validate_image_accessibility!(id, asset)

    sources = object!(asset["sources"], "image #{id} sources")
    exact_keys!(sources, IMAGE_FORMATS.keys, required: IMAGE_FORMATS.keys, label: "image #{id} sources")
    IMAGE_FORMATS.each do |format, (content_type, extension)|
      descriptors = array!(sources[format], "image #{id} #{format} sources")
      raise InvalidManifest, "Image #{id} #{format} sources are empty" if descriptors.empty?

      previous_width = 0
      descriptors.each do |descriptor|
        validate_image_descriptor!(id, format, content_type, extension, descriptor)
        width = descriptor.fetch("width")
        raise InvalidManifest, "Image #{id} #{format} sources are not width-ordered" if width <= previous_width
        raise InvalidManifest, "Image #{id} #{format} source exceeds asset dimensions" if width > asset["width"] || descriptor.fetch("height") > asset["height"]

        previous_width = width
      end
      unless descriptors.last.fetch("width") == asset["width"]
        raise InvalidManifest, "Image #{id} #{format} sources omit the full width"
      end
    end
  end

  def validate_image_accessibility!(id, asset)
    if asset["alt"].empty?
      unless asset["decorative"] == true
        raise InvalidManifest, "Image #{id} needs alt text or decorative=true"
      end
    elsif asset.key?("decorative")
      raise InvalidManifest, "Image #{id} cannot be decorative with nonempty alt text"
    end
  end

  def validate_image_descriptor!(id, format, content_type, extension, descriptor)
    descriptor = object!(descriptor, "image #{id} #{format} descriptor")
    descriptor_keys!(descriptor, "image #{id} #{format} descriptor")
    positive_integer!(descriptor["width"], "image #{id} #{format} width")
    positive_integer!(descriptor["height"], "image #{id} #{format} height")
    positive_integer!(descriptor["bytes"], "image #{id} #{format} bytes")
    unless descriptor["contentType"] == content_type
      raise InvalidManifest, "Image #{id} #{format} has the wrong content type"
    end
    pattern = %r{\A/media/#{Regexp.escape(id)}/#{SHA256}-w#{descriptor["width"]}\.#{extension}\z}
    path!(descriptor["path"], pattern, "image #{id} #{format}")
  end

  def validate_video!(id, asset)
    exact_keys!(asset,
      %w[kind sourceSha256 title description sourceDurationMs clipStartMs clipEndMs durationMs video poster captions],
      required: %w[kind sourceSha256 title description sourceDurationMs clipStartMs clipEndMs durationMs video poster captions],
      label: "video #{id}")
    sha256!(asset["sourceSha256"], "video #{id} source checksum")
    nonempty_string!(asset["title"], "video #{id} title")
    nonempty_string!(asset["description"], "video #{id} description")
    %w[sourceDurationMs clipEndMs durationMs].each do |key|
      positive_integer!(asset[key], "video #{id} #{key}")
    end
    nonnegative_integer!(asset["clipStartMs"], "video #{id} clipStartMs")
    unless asset["clipStartMs"] < asset["clipEndMs"] && asset["clipEndMs"] <= asset["sourceDurationMs"]
      raise InvalidManifest, "Video #{id} has invalid clip bounds"
    end
    if (asset["durationMs"] - (asset["clipEndMs"] - asset["clipStartMs"])).abs > 100
      raise InvalidManifest, "Video #{id} duration does not match its clip bounds"
    end

    video = validate_video_descriptor!(id, asset["video"])
    validate_poster_descriptor!(id, asset["poster"], video)
    validate_captions!(id, asset["captions"])
  end

  def validate_video_descriptor!(id, descriptor)
    descriptor = object!(descriptor, "video #{id} descriptor")
    descriptor_keys!(descriptor, "video #{id} descriptor")
    positive_integer!(descriptor["bytes"], "video #{id} bytes")
    positive_integer!(descriptor["width"], "video #{id} width")
    positive_integer!(descriptor["height"], "video #{id} height")
    unless descriptor["width"].even? && descriptor["height"].even? && descriptor["width"] <= 1920 && descriptor["height"] <= 1080
      raise InvalidManifest, "Video #{id} has invalid dimensions"
    end
    raise InvalidManifest, "Video #{id} has the wrong content type" unless descriptor["contentType"] == "video/mp4"

    pattern = %r{\A/media/#{Regexp.escape(id)}/#{SHA256}-#{descriptor["width"]}x#{descriptor["height"]}\.mp4\z}
    path!(descriptor["path"], pattern, "video #{id}")
    descriptor
  end

  def validate_poster_descriptor!(id, descriptor, video)
    descriptor = object!(descriptor, "video #{id} poster")
    descriptor_keys!(descriptor, "video #{id} poster")
    %w[bytes width height].each { |key| positive_integer!(descriptor[key], "video #{id} poster #{key}") }
    unless descriptor["contentType"] == "image/jpeg"
      raise InvalidManifest, "Video #{id} poster has the wrong content type"
    end
    unless descriptor.values_at("width", "height") == video.values_at("width", "height")
      raise InvalidManifest, "Video #{id} poster dimensions do not match"
    end
    path!(descriptor["path"], %r{\A/media/#{Regexp.escape(id)}/#{SHA256}-poster\.jpg\z}, "video #{id} poster")
  end

  def validate_captions!(id, captions)
    languages = []
    array!(captions, "video #{id} captions").each do |caption|
      caption = object!(caption, "video #{id} caption")
      exact_keys!(caption, %w[path contentType bytes language label],
        required: %w[path contentType bytes language label], label: "video #{id} caption")
      positive_integer!(caption["bytes"], "video #{id} caption bytes")
      nonempty_string!(caption["language"], "video #{id} caption language")
      nonempty_string!(caption["label"], "video #{id} caption label")
      unless caption["language"].match?(/\A[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\z/)
        raise InvalidManifest, "Video #{id} has an invalid caption language"
      end
      language = caption["language"].downcase
      raise InvalidManifest, "Video #{id} has duplicate caption language #{language}" if languages.include?(language)
      raise InvalidManifest, "Video #{id} caption has the wrong content type" unless caption["contentType"] == "text/vtt; charset=utf-8"

      path!(caption["path"], %r{\A/media/#{Regexp.escape(id)}/#{SHA256}-#{Regexp.escape(language)}\.vtt\z}, "video #{id} caption")
      languages << language
    end
  end

  def descriptor_keys!(descriptor, label)
    exact_keys!(descriptor, %w[path contentType bytes width height],
      required: %w[path contentType bytes width height], label: label)
  end

  def exact_keys!(object, allowed, required:, label:)
    missing = required - object.keys
    extra = object.keys - allowed
    raise InvalidManifest, "#{label} is missing #{missing.join(", ")}" if missing.any?
    raise InvalidManifest, "#{label} has unsupported fields: #{extra.join(", ")}" if extra.any?
  end

  def validate_asset_id!(id)
    raise InvalidAssetId, "Unsafe media asset ID: #{id.inspect}" unless id.is_a?(String) && id.match?(ASSET_ID)
  end

  def path!(value, pattern, label)
    raise InvalidManifest, "#{label} has an unsafe or mismatched path" unless value.is_a?(String) && value.match?(pattern)
  end

  def sha256!(value, label)
    raise InvalidManifest, "#{label} is invalid" unless value.is_a?(String) && value.match?(/\A#{SHA256}\z/)
  end

  def object!(value, label)
    raise InvalidManifest, "#{label} must be an object" unless value.is_a?(Hash)
    value
  end

  def array!(value, label)
    raise InvalidManifest, "#{label} must be an array" unless value.is_a?(Array)
    value
  end

  def string!(value, label)
    raise InvalidManifest, "#{label} must be a string" unless value.is_a?(String)
  end

  def nonempty_string!(value, label)
    string!(value, label)
    raise InvalidManifest, "#{label} must not be empty" if value.strip.empty?
  end

  def positive_integer!(value, label)
    raise InvalidManifest, "#{label} must be a positive integer" unless value.is_a?(Integer) && value.positive?
  end

  def nonnegative_integer!(value, label)
    raise InvalidManifest, "#{label} must be a nonnegative integer" unless value.is_a?(Integer) && value >= 0
  end

  def deep_copy(value)
    case value
    when Hash then value.to_h { |key, child| [ key.to_s, deep_copy(child) ] }
    when Array then value.map { |child| deep_copy(child) }
    else value
    end
  end

  def deep_freeze(value)
    case value
    when Hash then value.each { |key, child| key.freeze; deep_freeze(child) }
    when Array then value.each { |child| deep_freeze(child) }
    end
    value.freeze
  end
end
