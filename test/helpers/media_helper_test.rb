require "test_helper"

class MediaHelperTest < ActionView::TestCase
  tests MediaHelper

  setup do
    @media_catalog = MediaCatalog.new(manifest: MediaManifestFixture.manifest)
  end

  test "picture renders ordered root-relative sources, dimensions, alt text, and lazy defaults" do
    fragment = html_fragment(
      portfolio_picture("rings/home/hero", sizes: "(min-width: 60rem) 60rem, 100vw")
    )
    sources = fragment.css("picture > source")
    assert_equal %w[image/avif image/webp image/jpeg], sources.map { |source| source["type"] }
    assert_equal [
      "/media/rings/home/hero/#{"a" * 64}-w480.avif 480w",
      "/media/rings/home/hero/#{"a" * 64}-w1200.avif 1200w"
    ].join(", "), sources.first["srcset"]
    assert sources.all? { |source| source["sizes"] == "(min-width: 60rem) 60rem, 100vw" }

    image = fragment.at_css("picture > img")
    assert_equal "/media/rings/home/hero/#{"c" * 64}-w1200.jpg", image["src"]
    assert_equal "Portrait in the studio", image["alt"]
    assert_equal "1200", image["width"]
    assert_equal "800", image["height"]
    assert_equal "lazy", image["loading"]
    assert_equal "(min-width: 60rem) 60rem, 100vw", image["sizes"]
  end

  test "picture honors hero loading overrides and manifest accessibility" do
    fragment = html_fragment(
      portfolio_picture(
        "rings/home/hero",
        sizes: "100vw",
        loading: "eager",
        fetchpriority: "high",
        alt: "Caller override",
        width: 1,
        height: 1,
        class: "home__hero"
      )
    )
    image = fragment.at_css("img.home__hero")
    assert_equal "eager", image["loading"]
    assert_equal "high", image["fetchpriority"]
    assert_equal "Portrait in the studio", image["alt"]
    assert_equal "1200", image["width"]
    assert_equal "800", image["height"]

    manifest = MediaManifestFixture.manifest
    manifest["assets"]["rings/home/hero"] = MediaManifestFixture.decorative_image
    @media_catalog = MediaCatalog.new(manifest: manifest)
    decorative = html_fragment(
      portfolio_picture("rings/home/hero", sizes: "100vw")
    ).at_css("img")
    assert_equal "", decorative["alt"]
  end

  test "picture requires a caller-supplied sizes contract" do
    error = assert_raises(ArgumentError) do
      portfolio_picture("rings/home/hero")
    end
    assert_match "requires sizes", error.message
  end

  test "video renders controls, poster, captions, dimensions, and accessible description" do
    fragment = html_fragment(
      portfolio_video("videos/studio-tour", class: "studio-tour", autoplay: true)
    )
    video = fragment.at_css("figure.portfolio-video > video.studio-tour")
    assert video.key?("controls")
    assert video.key?("playsinline")
    refute video.key?("autoplay")
    assert_equal "metadata", video["preload"]
    assert_equal "/media/videos/studio-tour/#{"d" * 64}-1280x720.mp4", video["src"]
    assert_equal "/media/videos/studio-tour/#{"e" * 64}-poster.jpg", video["poster"]
    assert_equal "1280", video["width"]
    assert_equal "720", video["height"]
    assert_equal "Studio tour", video["aria-label"]

    caption = fragment.at_css("figcaption##{video["aria-describedby"]}")
    assert_includes caption.text, "Studio tour"
    assert_includes caption.text, "A short walk through the studio"
    track = video.at_css("track[kind='captions']")
    assert_equal "en-US", track["srclang"]
    assert_equal "English", track["label"]
    assert_equal "/media/videos/studio-tour/#{"f" * 64}-en-us.vtt", track["src"]
  end

  test "generic helper dispatches by kind" do
    assert html_fragment(
      portfolio_media("rings/home/hero", sizes: "100vw")
    ).at_css("picture")
    assert html_fragment(
      portfolio_media("videos/studio-tour", sizes: "100vw")
    ).at_css("video:not([sizes])")
  end

  private

  def html_fragment(html)
    Nokogiri::HTML5.fragment(html)
  end
end
