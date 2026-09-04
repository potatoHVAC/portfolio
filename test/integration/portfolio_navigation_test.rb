require "test_helper"

class PortfolioNavigationTest < ActionDispatch::IntegrationTest
  test "every catalog route renders a single page landmark and heading" do
    PortfolioCatalog.current.public_paths.each do |path|
      get path

      assert_response :success, "expected #{path} to render"
      assert_equal 1, css_select("main#main-content").size, "expected one main on #{path}"
      assert_equal 1, css_select("h1").size, "expected one h1 on #{path}"
    end
  end

  test "the gallery directory groups destinations without combining media" do
    get galleries_path

    assert_equal 3, css_select("section.gallery-group").size
    assert_equal 10, css_select("article.gallery-card").size
    assert_empty css_select("section.media-gallery")
    assert_empty css_select("picture, video")
  end

  test "project and gallery pages retain their section accent" do
    get disco_chief_path
    assert_response :success
    assert_equal 1, css_select("main.accent--spectacle").size
    assert_equal "Disco Chief", css_select("h1").first.text

    get gallery_path("damascus-rings")
    assert_response :success
    assert_equal 1, css_select("main.accent--ember").size
    assert_includes response.body, "This gallery is being prepared."
  end

  test "unknown galleries return not found" do
    get gallery_path("not-in-the-catalog")

    assert_response :not_found
  end

  test "the sitemap is derived from the public catalog" do
    get "/sitemap.xml"

    assert_response :success
    assert_equal "application/xml", response.media_type
    locations = Nokogiri::XML(response.body).xpath("//*[local-name()='loc']").map(&:text)
    expected = PortfolioCatalog.current.public_paths.map { |path| "#{ApplicationHelper::SITE_ORIGIN}#{path}" }
    assert_equal expected, locations
  end

  test "every internal primary-navigation destination is public" do
    get root_path
    destinations = css_select("nav[aria-label='Primary navigation'] a").map { |link| link["href"] }

    assert_equal ApplicationHelper::NAVIGATION.map(&:last), destinations
    destinations.each { |path| assert_includes PortfolioCatalog.current.public_paths, path }
  end
end
