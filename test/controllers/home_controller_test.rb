require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "the home page leads with LED work and the full site navigation" do
    get root_url

    assert_response :success
    assert_equal "Built to glow.Forged to last.", css_select("h1").first.text.strip
    assert_includes response.body, "Primary practice"
    assert_includes response.body, "Instrument Art"
    assert_includes response.body, "Cadenza"
    assert_equal ApplicationHelper::NAVIGATION.map(&:first), css_select("nav[aria-label='Primary navigation'] a").map(&:text)
    assert_equal 1, css_select("main#main-content").size
    assert_equal 1, css_select("h1").size
  end

  test "the home page publishes canonical and social metadata" do
    get root_url

    assert_equal "https://speerd.com/", css_select("link[rel='canonical']").first["href"]
    assert_equal "https://speerd.com/", css_select("meta[property='og:url']").first["content"]
    assert_equal "Light, costume, and metal — SPEERD", css_select("meta[property='og:title']").first["content"]
    assert_equal 1, css_select("a.skip-link[href='#main-content']").size
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
