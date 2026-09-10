require "test_helper"

class PortfolioNavigationTest < ActionDispatch::IntegrationTest
  test "every catalog route renders a single page landmark and heading" do
    paths = PortfolioCatalog.current.public_paths + BuildBookCatalog.current.public_paths

    paths.each do |path|
      get path

      assert_response :success, "expected #{path} to render"
      assert_equal 1, css_select("main#main-content").size, "expected one main on #{path}"
      assert_equal 1, css_select("h1").size, "expected one h1 on #{path}"
    end
  end

  test "the gallery directory groups destinations without combining media" do
    get galleries_path

    assert_equal 4, css_select("section.gallery-group").size
    assert_equal 11, css_select("article.gallery-card").size
    assert_empty css_select("section.media-gallery")
    assert_empty css_select("picture, video")
  end

  test "a gallery without a section still lists and renders on its own" do
    get galleries_path
    assert_select "section.gallery-group h2", text: "Outside the disciplines"
    assert_select "a[href=?]", "/galleries/misc-art"

    get gallery_path("misc-art")
    assert_response :success
    assert_equal "Miscellaneous Art", css_select("h1").first.text
    assert_equal "Galleries", css_select("p.breadcrumb").first.text.strip
  end

  test "project and gallery pages retain their section accent" do
    get disco_chief_path
    assert_response :success
    assert_equal 1, css_select("main.accent--spectacle").size
    assert_equal "Disco Chief", css_select("h1").first.text

    get gallery_path("damascus-rings")
    assert_response :success
    assert_equal 1, css_select("main.accent--ember").size
    assert_predicate css_select("article.media-gallery__item"), :any?

    get gallery_path("cadenza")
    assert_response :success
    assert_equal 1, css_select("main.accent--electric").size
    assert_predicate css_select("article.media-gallery__item"), :any?
  end

  test "a gallery holding no media renders the pending state" do
    emptied = YAML.safe_load_file(
      Rails.root.join("config/portfolio.yml"),
      permitted_classes: [],
      permitted_symbols: [],
      aliases: false
    )
    gallery = emptied["galleries"].find { |entry| entry["id"] == "cadenza" }
    gallery["media_ids"] = []
    gallery["cover_media_id"] = nil
    gallery["credits"] = []

    PortfolioCatalog.instance_variable_set(:@current, PortfolioCatalog.new(catalog: emptied))
    get gallery_path("cadenza")

    assert_response :success
    assert_includes response.body, "This gallery is being prepared."
    assert_empty css_select("section.media-gallery")
  ensure
    PortfolioCatalog.reset!
  end

  test "gallery tiles open a lightbox and never nest video controls" do
    get gallery_path("damascus-rings")
    assert_response :success

    items = css_select("article.media-gallery__item")
    assert_equal items.size, css_select("button.media-gallery__trigger").size
    assert_equal items.size, response.body.scan("data-lightbox-full").size
    assert_predicate css_select("span.media-tile__play"), :any?
    assert_empty css_select("button.media-gallery__trigger video")
    assert_predicate css_select("script[src*='lightbox']"), :any?
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
    paths = PortfolioCatalog.current.public_paths + BuildBookCatalog.current.public_paths
    expected = paths.map { |path| "#{ApplicationHelper::SITE_ORIGIN}#{path}" }
    assert_equal expected, locations
  end

  test "every internal primary-navigation destination is public" do
    get root_path
    destinations = css_select("nav[aria-label='Primary navigation'] a").map { |link| link["href"] }

    assert_equal ApplicationHelper::NAVIGATION.map(&:last), destinations
    destinations.each { |path| assert_includes PortfolioCatalog.current.public_paths, path }
  end

  test "the build book renders one heading per section behind a single h1" do
    get russell_glow_build_book_path

    assert_response :success
    assert_equal 1, css_select("h1").size
    assert_equal "Russell Glow", css_select("h1").first.text
    assert_equal 7, css_select("section.build-book-section").size
    assert_equal 7, css_select("nav.build-book-contents a").size
    assert_equal 32, css_select("figure.build-book-figure").size
    assert_equal 1, css_select("main.accent--spectacle").size
  end

  test "the build book contents nav anchors every section it lists" do
    get russell_glow_build_book_path

    anchors = css_select("nav.build-book-contents a").map { |a| a["href"].delete_prefix("#") }
    ids = css_select("section.build-book-section").map { |s| s["id"] }

    assert_equal ids, anchors
    assert_equal ids.uniq, ids
  end

  test "the project page links its build book and omits the band without one" do
    get russell_glow_path
    assert_response :success
    assert_select "section.project-build-book a[href=?]", "/cosplay/russell-glow/build-book"

    get darth_daddy_path
    assert_response :success
    assert_empty css_select("section.project-build-book")
  end

  test "a source figure carries its citation" do
    get russell_glow_build_book_path

    credits = css_select("figure.build-book-figure .credit__name").map(&:text)
    assert_equal 2, credits.size
    assert(credits.all? { |credit| credit.include?("Gladiator") })
  end

  test "gallery credit groups name the photographer once and mark their tiles" do
    get gallery_path("russell-glow")
    assert_response :success

    banner = css_select(".gallery-credits .credit__name")
    assert_equal 1, banner.size
    assert_equal "Girl with the Blue Hair Photography", banner.first.text
    assert_equal "https://linktr.ee/girl_with_the_blue_hair", banner.first["href"]
    credited = PortfolioCatalog.current.gallery!("russell-glow").fetch("credits")
      .sum { |credit| credit.fetch("media_ids").size }
    assert_equal credited, css_select("article.media-gallery__item .credit--tile").size

    get gallery_path("disco-chief")
    assert_response :success
    assert_equal "oke.bokeh", css_select(".gallery-credits .credit__name").first.text
    assert_equal 5, css_select("article.media-gallery__item .credit--tile").size
  end

  test "an uncredited gallery renders no credit markup" do
    get gallery_path("damascus-rings")

    assert_response :success
    assert_empty css_select(".gallery-credits")
    assert_empty css_select(".credit")
  end

  test "the credited photographs lead their galleries" do
    get gallery_path("russell-glow")
    first = css_select("article.media-gallery__item").first

    assert_predicate first.css(".credit--tile"), :any?
  end

  test "the sitemap carries build book paths" do
    get "/sitemap.xml"

    assert_response :success
    assert_includes response.body, "/cosplay/russell-glow/build-book"
  end

  test "a reveal band sits between sections and renders its photo as an image" do
    get root_path

    assert_response :success
    assert_equal 1, css_select("section.reveal-band").size
    assert_equal 1, css_select("section.reveal-band .reveal-band__image picture img").size
    assert_predicate css_select("section.reveal-band picture source[type='image/avif']"), :any?
  end

  # The edge CSP sets style-src 'self', so the band's height cannot ride in on
  # an inline aspect-ratio; the spacer's viewBox carries the photo's ratio.
  test "a reveal band carries a spacer holding its photo's ratio" do
    get root_path

    spacer = css_select("section.reveal-band svg.reveal-band__sizer")
    assert_equal 1, spacer.size
    # Nokogiri parses as HTML, which lowercases the attribute name.
    assert_equal "0 0 4096 3072", spacer.first["viewbox"]
  end

  # The edge CSP sets style-src 'self', so a browser drops inline style
  # attributes and whatever they carried never renders.
  test "no public page carries an inline style attribute" do
    paths = PortfolioCatalog.current.public_paths + BuildBookCatalog.current.public_paths
    offenders = paths.select do |path|
      get path
      response.body.include?(" style=")
    end

    assert_empty offenders, "inline styles are dropped by the edge CSP"
  end
end
