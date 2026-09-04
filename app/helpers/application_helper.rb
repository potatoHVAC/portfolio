module ApplicationHelper
  SITE_ORIGIN = "https://speerd.com"
  NAVIGATION = [
    [ "LED Art", "/led-art" ],
    [ "Cosplay", "/cosplay" ],
    [ "Forge", "/forge" ],
    [ "Galleries", "/galleries" ],
    [ "About", "/about" ],
    [ "Contact", "/contact" ]
  ].freeze
  SPECTRUM_STOPS = 7

  def set_page_meta(title:, description:)
    content_for(:title, title)
    content_for(:description, description)
  end

  def document_title
    page_title = content_for(:title)
    page_title.present? ? "#{page_title} — #{portfolio_catalog.site.fetch("name")}" : portfolio_catalog.site.fetch("tagline")
  end

  def page_description
    content_for(:description).presence || portfolio_catalog.site.fetch("description")
  end

  def canonical_url
    "#{SITE_ORIGIN}#{request.path == "/sitemap" ? "/sitemap.xml" : request.path}"
  end

  def navigation_link(label, path)
    active = request.path == path || (path != "/" && request.path.start_with?("#{path}/"))
    options = { class: "site-nav__link" }
    options[:aria] = { current: "page" } if active
    link_to label, path, **options
  end

  # Walks the spectrum for numbered details that belong to the site as a whole
  # rather than to one section, which keeps its own accent.
  def spectrum_class(index)
    "spectrum--#{(index % SPECTRUM_STOPS) + 1}"
  end

  def accent_class(entry)
    accent = entry["accent"] || portfolio_catalog.section!(entry.fetch("section_id")).fetch("accent")
    "accent--#{accent}"
  end
end
