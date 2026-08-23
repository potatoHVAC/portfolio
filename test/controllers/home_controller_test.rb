require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "the home page renders the tagline" do
    get root_url

    assert_response :success
    assert_includes response.body, I18n.t("site.tagline")
  end

  test "the home page renders the hero image with fixed dimensions" do
    get root_url

    image = css_select("img.home__hero").first
    assert image, "expected a hero image on the home page"

    # Digest-stamped: proves Propshaft resolved the asset rather than emitting a
    # bare path that would 404 once assets are precompiled into the image.
    assert_match %r{\A/assets/hero-\w+\.jpg\z}, image["src"]

    # Explicit dimensions reserve the space and prevent layout shift.
    assert_equal "1200", image["width"]
    assert_equal "800", image["height"]
    refute_empty image["alt"].to_s
  end

  test "the health endpoint reports up" do
    get rails_health_check_url

    assert_response :success
  end
end
