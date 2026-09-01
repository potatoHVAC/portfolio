require "test_helper"

class MediaCatalogTest < ActiveSupport::TestCase
  test "fetches nested typed assets and freezes the validated manifest" do
    catalog = MediaCatalog.new(manifest: MediaManifestFixture.manifest)

    image = catalog.fetch!("rings/home/hero", kind: :image)
    assert_equal "Portrait in the studio", image.fetch("alt")
    assert_predicate image, :frozen?
    assert_predicate image.fetch("sources").fetch("avif"), :frozen?
    assert_predicate catalog.assets.keys.first, :frozen?
    assert_raises(FrozenError) { image["alt"] = "Changed" }

    video = catalog.fetch!("videos/studio-tour", kind: "video")
    assert_equal 21_500, video.fetch("durationMs")
  end

  test "rejects unsafe, unknown, mismatched, and unsupported requests" do
    catalog = MediaCatalog.new(manifest: MediaManifestFixture.manifest)

    assert_raises(MediaCatalog::InvalidAssetId) { catalog.fetch!("../hero") }
    assert_raises(MediaCatalog::InvalidAssetId) { catalog.fetch!("rings//hero") }
    assert_raises(MediaCatalog::UnknownAsset) { catalog.fetch!("rings/missing") }
    assert_raises(MediaCatalog::KindMismatch) do
      catalog.fetch!("rings/home/hero", kind: :video)
    end
    assert_raises(ArgumentError) { catalog.fetch!("rings/home/hero", kind: :audio) }
  end

  test "rejects unsupported versions and structurally incomplete descriptors" do
    unsupported = MediaManifestFixture.manifest.merge("version" => 2)
    error = assert_raises(MediaCatalog::InvalidManifest) do
      MediaCatalog.new(manifest: unsupported)
    end
    assert_match "Unsupported media manifest version", error.message

    incomplete = MediaManifestFixture.manifest
    incomplete["assets"]["rings/home/hero"]["sources"]["jpeg"][0].delete("height")
    error = assert_raises(MediaCatalog::InvalidManifest) do
      MediaCatalog.new(manifest: incomplete)
    end
    assert_match "missing height", error.message

    extra_root = MediaManifestFixture.manifest.merge("bucket" => "forbidden")
    error = assert_raises(MediaCatalog::InvalidManifest) do
      MediaCatalog.new(manifest: extra_root)
    end
    assert_match "unsupported fields", error.message
  end

  test "rejects source ordering, dimension, accessibility, and path drift" do
    unordered = MediaManifestFixture.manifest
    unordered["assets"]["rings/home/hero"]["sources"]["webp"].reverse!
    assert_raises(MediaCatalog::InvalidManifest) { MediaCatalog.new(manifest: unordered) }

    oversized = MediaManifestFixture.manifest
    oversized["assets"]["videos/studio-tour"]["video"]["width"] = 2000
    assert_raises(MediaCatalog::InvalidManifest) { MediaCatalog.new(manifest: oversized) }

    inaccessible = MediaManifestFixture.manifest
    inaccessible["assets"]["rings/home/hero"]["alt"] = ""
    assert_raises(MediaCatalog::InvalidManifest) { MediaCatalog.new(manifest: inaccessible) }

    unsafe = MediaManifestFixture.manifest
    unsafe["assets"]["videos/studio-tour"]["poster"]["path"] = "https://example.com/poster.jpg"
    assert_raises(MediaCatalog::InvalidManifest) { MediaCatalog.new(manifest: unsafe) }
  end

  test "accepts the publisher's 2400 pixel cap for wider source images" do
    capped = MediaManifestFixture.manifest
    image = capped.fetch("assets").fetch("rings/home/hero")
    image["width"] = 3072
    image["height"] = 4096
    image.fetch("sources").each_value do |descriptors|
      largest = descriptors.last
      largest["width"] = 2400
      largest["height"] = 3200
      largest["path"] = largest.fetch("path").sub("-w1200.", "-w2400.")
    end

    assert_nothing_raised { MediaCatalog.new(manifest: capped) }

    capped.fetch("assets").fetch("rings/home/hero").fetch("sources").fetch("avif").pop
    error = assert_raises(MediaCatalog::InvalidManifest) do
      MediaCatalog.new(manifest: capped)
    end
    assert_match "omit the largest permitted width", error.message
  end

  test "loads the committed manifest without initializing an AWS client" do
    aws_loaded_before = Object.const_defined?(:Aws)
    catalog = MediaCatalog.new

    assert_equal aws_loaded_before, Object.const_defined?(:Aws)
    assert_equal 2, catalog.assets.size
    assert_equal "image", catalog.fetch!("validation/p-20231021-194531").fetch("kind")
    assert_equal "video", catalog.fetch!("validation/v-20231013-144526-es3").fetch("kind")
    assert_raises(MediaCatalog::UnknownAsset) { catalog.fetch!("rings/home/hero") }
  end
end
