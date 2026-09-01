require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "the home page renders the tagline" do
    get root_url

    assert_response :success
    assert_includes response.body, I18n.t("site.tagline")
  end

  test "the home page renders the published responsive hero" do
    get root_url

    image = css_select("img.home__hero").first
    assert image, "expected a hero image on the home page"

    assert_match %r{\A/media/validation/p-20231021-194531/}, image["src"]
    refute_match %r{\A/assets/}, image["src"]
    assert_equal "3072", image["width"]
    assert_equal "4096", image["height"]
    assert_equal "", image["alt"]
    assert_equal "eager", image["loading"]
    assert_equal "high", image["fetchpriority"]
    assert_equal "(min-width: 72rem) 64rem, 100vw", image["sizes"]

    sources = css_select("picture source")
    assert_equal %w[image/avif image/webp image/jpeg], sources.map { |source| source["type"] }
    assert sources.all? { |source| source["srcset"].include?("/media/validation/p-20231021-194531/") }
    assert sources.all? { |source| source["srcset"].split(", ").size == 5 }
  end

  test "the home page renders the published selected video" do
    get root_url

    video = css_select("figure.portfolio-video > video.home__video").first
    assert video, "expected a video on the home page"
    assert video.key?("controls")
    assert video.key?("playsinline")
    refute video.key?("autoplay")
    assert_equal "metadata", video["preload"]
    assert_match %r{\A/media/validation/v-20231013-144526-es3/}, video["src"]
    assert_match %r{\A/media/validation/v-20231013-144526-es3/}, video["poster"]
    assert_equal "608", video["width"]
    assert_equal "1080", video["height"]
    assert_equal "Video pipeline validation", video["aria-label"]

    caption = css_select("figcaption##{video["aria-describedby"]}").first
    assert caption
    assert_includes caption.text, "Video pipeline validation"
    assert_includes caption.text, "A short video used to validate media publication."
    assert_empty css_select("video.home__video track")
  end

  test "the health endpoint reports up" do
    get rails_health_check_url

    assert_response :success
  end

  test "application views can render root-relative manifest media without AWS" do
    aws_loaded_before = Object.const_defined?(:Aws)
    catalog = MediaCatalog.new(manifest: MediaManifestFixture.manifest)
    view = ApplicationController.helpers
    view.instance_variable_set(:@media_catalog, catalog)
    html = view.portfolio_picture("rings/home/hero", sizes: "100vw")

    image = Nokogiri::HTML.fragment(html).at_css("picture img")
    assert image
    assert_match %r{\A/media/rings/home/hero/}, image["src"]
    refute_match %r{\A/assets/}, image["src"]
    assert_equal aws_loaded_before, Object.const_defined?(:Aws)
  end
end
