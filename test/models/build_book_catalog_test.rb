require "test_helper"

class BuildBookCatalogTest < ActiveSupport::TestCase
  # Stands in for the manifest so schema tests do not depend on published media.
  class PermissiveMedia
    def fetch!(id, **) = { "id" => id }
  end

  setup do
    @book = YAML.safe_load_file(
      Rails.root.join("config/build_books/russell-glow.yml"),
      permitted_classes: [],
      permitted_symbols: [],
      aliases: false
    )
    @portfolio = PortfolioCatalog.current
  end

  test "loads the shipped build book and freezes it" do
    catalog = build_catalog([ @book ])

    assert_equal 1, catalog.books.size
    assert_equal "russell-glow", catalog.for_project("russell-glow").fetch("project_id")
    assert_equal 7, catalog.for_project("russell-glow").fetch("sections").size
    assert_equal [ "/cosplay/russell-glow/build-book" ], catalog.public_paths
    assert_predicate catalog.books.first, :frozen?
    assert_raises(FrozenError) { catalog.books.first["title"] = "Changed" }
  end

  test "returns nil for a project without a build book and raises when asked to insist" do
    catalog = build_catalog([ @book ])

    assert_nil catalog.for_project("darth-daddy")
    assert_raises(BuildBookCatalog::UnknownEntry) { catalog.build_book!("darth-daddy") }
  end

  test "rejects unsupported versions and unexpected fields" do
    unsupported = copy_book
    unsupported["version"] = 2
    assert_match "Unsupported build book version", error_for(unsupported)

    extra = copy_book
    extra["html"] = "<strong>no</strong>"
    assert_match "Build book fields must be", error_for(extra)

    stray = copy_book
    stray["sections"][0]["beats"][0]["figures"][0]["photographer"] = "someone"
    assert_match "figure fields must be", error_for(stray)
  end

  test "rejects an unknown project and duplicate books for one project" do
    orphan = copy_book
    orphan["project_id"] = "not-a-project"
    assert_match "unknown project", error_for(orphan)

    error = assert_raises(BuildBookCatalog::InvalidCatalog) { build_catalog([ copy_book, copy_book ]) }
    assert_match "Duplicate build book for project", error.message
  end

  test "rejects duplicate and malformed section ids" do
    duplicate = copy_book
    duplicate["sections"][1]["id"] = duplicate["sections"][0]["id"]
    assert_match "repeats section id", error_for(duplicate)

    malformed = copy_book
    malformed["sections"][0]["id"] = "Not Kebab"
    assert_match "invalid section id", error_for(malformed)
  end

  test "rejects empty sections and beats" do
    no_sections = copy_book
    no_sections["sections"] = []
    assert_match "has no sections", error_for(no_sections)

    no_beats = copy_book
    no_beats["sections"][0]["beats"] = []
    assert_match "has no beats", error_for(no_beats)
  end

  test "requires a caption on every figure and rejects a non-https credit url" do
    uncaptioned = copy_book
    uncaptioned["sections"][0]["beats"][0]["figures"][0]["caption"] = ""
    assert_match "figure caption", error_for(uncaptioned)

    insecure = copy_book
    insecure["sections"][0]["credit"] = "Someone"
    insecure["sections"][0]["credit_url"] = "http://example.com"
    assert_match "must be an https URL", error_for(insecure)
  end

  test "carries a credit through to any section or figure that declares one" do
    credited = copy_book
    credited["sections"][0]["credit"] = "A Photographer"
    credited["sections"][0]["credit_url"] = "https://example.com/portfolio"
    section = build_catalog([ credited ]).for_project("russell-glow").fetch("sections").first

    assert_equal "A Photographer", section.fetch("credit")
    assert_equal "https://example.com/portfolio", section.fetch("credit_url")
  end

  test "every figure in the shipped book carries a caption" do
    figures = @book.fetch("sections").flat_map { |s| s.fetch("beats").flat_map { |b| b["figures"] || [] } }

    assert_equal 32, figures.size
    assert_empty figures.reject { |figure| figure["caption"].present? }
  end

  private

  def build_catalog(books)
    BuildBookCatalog.new(books: books, portfolio_catalog: @portfolio, media_catalog: PermissiveMedia.new)
  end

  def copy_book = Marshal.load(Marshal.dump(@book))

  def error_for(book)
    assert_raises(BuildBookCatalog::InvalidCatalog) { build_catalog([ book ]) }.message
  end
end
