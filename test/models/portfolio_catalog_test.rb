require "test_helper"

class PortfolioCatalogTest < ActiveSupport::TestCase
  setup do
    @data = YAML.safe_load_file(
      Rails.root.join("config/portfolio.yml"),
      permitted_classes: [],
      permitted_symbols: [],
      aliases: false
    )
    @media_catalog = MediaCatalog.new
  end

  test "loads and freezes the public content graph without AWS" do
    aws_loaded_before = Object.const_defined?(:Aws)
    catalog = PortfolioCatalog.new(catalog: @data, media_catalog: @media_catalog)

    assert_equal 3, catalog.sections.size
    assert_equal 5, catalog.projects.size
    assert_equal 11, catalog.galleries.size
    assert_equal 23, catalog.public_paths.size
    assert_equal %w[instrument-art cadenza], catalog.featured_projects_for("led-art").pluck("id")
    assert_predicate catalog.site, :frozen?
    assert_predicate catalog.projects.first.fetch("stories"), :frozen?
    assert_raises(FrozenError) { catalog.site["name"] = "Changed" }
    assert_equal aws_loaded_before, Object.const_defined?(:Aws)
  end

  test "rejects unsupported versions and unexpected fields" do
    unsupported = copy_data
    unsupported["version"] = 2
    error = assert_raises(PortfolioCatalog::InvalidCatalog) { build_catalog(unsupported) }
    assert_match "Unsupported portfolio catalog version", error.message

    extra = copy_data
    extra["site"]["html"] = "<strong>no</strong>"
    error = assert_raises(PortfolioCatalog::InvalidCatalog) { build_catalog(extra) }
    assert_match "Site fields must be", error.message
  end

  test "rejects duplicate identifiers and paths" do
    duplicate_id = copy_data
    duplicate_id["galleries"][1]["id"] = duplicate_id["galleries"][0]["id"]
    assert_raises(PortfolioCatalog::InvalidCatalog) { build_catalog(duplicate_id) }

    duplicate_path = copy_data
    duplicate_path["projects"][0]["path"] = "/about"
    error = assert_raises(PortfolioCatalog::InvalidCatalog) { build_catalog(duplicate_path) }
    assert_match "Duplicate portfolio path", error.message
  end

  test "rejects unsafe paths and invalid relationships" do
    unsafe = copy_data
    unsafe["sections"][0]["path"] = "../led-art"
    assert_raises(PortfolioCatalog::InvalidCatalog) { build_catalog(unsafe) }

    unknown_section = copy_data
    unknown_section["projects"][0]["section_id"] = "missing"
    error = assert_raises(PortfolioCatalog::InvalidCatalog) { build_catalog(unknown_section) }
    assert_match "unknown section", error.message

    wrong_gallery = copy_data
    wrong_gallery["projects"][0]["gallery_id"] = "cosplay"
    error = assert_raises(PortfolioCatalog::InvalidCatalog) { build_catalog(wrong_gallery) }
    assert_match "invalid gallery", error.message
  end

  test "rejects missing media and a cover outside the gallery order" do
    missing_media = copy_data
    missing_media["galleries"][0]["media_ids"] = [ "missing/asset" ]
    error = assert_raises(PortfolioCatalog::InvalidCatalog) { build_catalog(missing_media) }
    assert_match "references invalid media", error.message

    missing_cover = copy_data
    gallery = missing_cover["galleries"][0]
    outside = @media_catalog.assets.keys.find { |id| gallery["media_ids"].exclude?(id) }
    gallery["cover_media_id"] = outside
    error = assert_raises(PortfolioCatalog::InvalidCatalog) { build_catalog(missing_cover) }
    assert_match "cover must be included", error.message
  end

  test "rejects an accent with no stylesheet counterpart" do
    unknown_accent = copy_data
    unknown_accent["sections"][0]["accent"] = "chartreuse"
    error = assert_raises(PortfolioCatalog::InvalidCatalog) { build_catalog(unknown_accent) }
    assert_match "accent must be one of", error.message
  end

  test "raises a typed error for unknown public entries" do
    catalog = build_catalog(copy_data)

    assert_raises(PortfolioCatalog::UnknownEntry) { catalog.section!("missing") }
    assert_raises(PortfolioCatalog::UnknownEntry) { catalog.project!("missing") }
    assert_raises(PortfolioCatalog::UnknownEntry) { catalog.gallery!("missing") }
  end

  test "gallery credits must name media the gallery actually lists" do
    stray = copy_data
    gallery = stray["galleries"].find { |entry| entry["id"] == "russell-glow" }
    gallery["credits"][0]["media_ids"] << "cosplay/darth-daddy/darth-daddy-001"
    error = assert_raises(PortfolioCatalog::InvalidCatalog) { build_catalog(stray) }
    assert_match "credits media it does not list", error.message
  end

  test "gallery credits may not claim one asset twice" do
    doubled = copy_data
    gallery = doubled["galleries"].find { |entry| entry["id"] == "russell-glow" }
    gallery["credits"] << gallery["credits"][0].merge("name" => "Someone Else")
    error = assert_raises(PortfolioCatalog::InvalidCatalog) { build_catalog(doubled) }
    assert_match "twice", error.message
  end

  test "gallery credits reject an empty group and a non-https url" do
    empty = copy_data
    empty["galleries"].find { |entry| entry["id"] == "russell-glow" }["credits"][0]["media_ids"] = []
    assert_match "lists no media", assert_raises(PortfolioCatalog::InvalidCatalog) { build_catalog(empty) }.message

    insecure = copy_data
    insecure["galleries"].find { |entry| entry["id"] == "russell-glow" }["credits"][0]["url"] = "http://example.com"
    assert_match "must be an https URL", assert_raises(PortfolioCatalog::InvalidCatalog) { build_catalog(insecure) }.message
  end

  test "credited media resolves to its group" do
    catalog = PortfolioCatalog.new(catalog: @data, media_catalog: @media_catalog)
    gallery = catalog.gallery!("russell-glow")
    index = catalog.gallery_credits_by_media_id(gallery)

    assert_equal 13, index.size
    assert_equal "Girl with the Blue Hair Photography",
                 index.fetch("cosplay/russell-glow/russell-glow-014").fetch("name")
    assert_nil index["cosplay/russell-glow/russell-glow-001"]
  end

  private

  def copy_data
    Marshal.load(Marshal.dump(@data))
  end

  def build_catalog(data)
    PortfolioCatalog.new(catalog: data, media_catalog: @media_catalog)
  end
end
