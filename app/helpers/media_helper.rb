module MediaHelper
  IMAGE_FORMATS = %w[avif webp jpeg].freeze

  def portfolio_media(id, **html_options)
    asset = media_catalog.fetch!(id)
    case asset.fetch("kind")
    when "image" then render_portfolio_picture(asset, html_options)
    when "video" then render_portfolio_video(id, asset, html_options)
    end
  end

  def portfolio_picture(id, **html_options)
    render_portfolio_picture(media_catalog.fetch!(id, kind: :image), html_options)
  end

  def portfolio_video(id, **html_options)
    render_portfolio_video(id, media_catalog.fetch!(id, kind: :video), html_options)
  end

  # Grid tile: a still for both kinds, so a tile never nests video controls.
  def portfolio_media_thumbnail(id, **html_options)
    asset = media_catalog.fetch!(id)
    case asset.fetch("kind")
    when "image" then render_portfolio_picture(asset, html_options)
    when "video" then render_portfolio_poster(asset, html_options)
    end
  end

  # One derivative path, for CSS backgrounds that cannot carry a srcset.
  def portfolio_media_backdrop(id, width: 2400)
    descriptors = media_catalog.fetch!(id, kind: :image).fetch("sources").fetch("jpeg")
    (descriptors.find { |descriptor| descriptor.fetch("width") >= width } || descriptors.last).fetch("path")
  end

  private

  def render_portfolio_poster(asset, html_options)
    poster = asset.fetch("poster")
    options = html_options.symbolize_keys.except(
      :src, :alt, :width, :height, :sizes, :autoplay, :muted, :loop
    )
    image = tag.img(
      **{ loading: "lazy" }.merge(options).merge(
        src: poster.fetch("path"),
        alt: asset.fetch("title"),
        width: poster.fetch("width"),
        height: poster.fetch("height")
      )
    )
    safe_join([ image, tag.span("", class: "media-tile__play", "aria-hidden": true) ])
  end

  def media_catalog
    @media_catalog ||= MediaCatalog.new
  end

  def render_portfolio_picture(asset, html_options)
    options = html_options.symbolize_keys
    sizes = options.delete(:sizes)
    raise ArgumentError, "portfolio_picture requires sizes:" if sizes.blank?

    sources = IMAGE_FORMATS.map do |format|
      descriptors = asset.fetch("sources").fetch(format)
      tag.source(
        type: descriptors.first.fetch("contentType"),
        srcset: descriptors.map { |descriptor| "#{descriptor.fetch("path")} #{descriptor.fetch("width")}w" }.join(", "),
        sizes: sizes
      )
    end
    fallback = asset.fetch("sources").fetch("jpeg").last
    image_options = { loading: "lazy" }.merge(
      options.except(:src, :alt, :width, :height, :sizes, :autoplay, :muted, :loop)
    ).merge(
      src: fallback.fetch("path"),
      alt: asset.fetch("alt"),
      width: asset.fetch("width"),
      height: asset.fetch("height"),
      sizes: sizes
    )
    content_tag(:picture, safe_join([ *sources, tag.img(**image_options) ]))
  end

  def render_portfolio_video(id, asset, html_options)
    description_id = next_video_description_id(id)
    video = asset.fetch("video")
    requested = html_options.symbolize_keys
    autoplay = requested[:autoplay].present?
    options = requested.except(
      :src, :poster, :width, :height, :sizes, :controls, :playsinline, :preload, :autoplay,
      :muted, :loop, :"aria-label", :"aria-describedby"
    ).merge(
      src: video.fetch("path"),
      poster: asset.fetch("poster").fetch("path"),
      width: video.fetch("width"),
      height: video.fetch("height"),
      controls: true,
      playsinline: true,
      preload: "metadata",
      "aria-label": asset.fetch("title"),
      "aria-describedby": description_id
    )
    # Autoplay starts muted and keeps controls, so sound can be turned on.
    options.merge!(autoplay: true, muted: true) if autoplay

    tracks = asset.fetch("captions").map do |caption|
      tag.track(
        kind: "captions",
        src: caption.fetch("path"),
        srclang: caption.fetch("language"),
        label: caption.fetch("label")
      )
    end
    caption = content_tag(:figcaption, id: description_id) do
      safe_join([ content_tag(:strong, asset.fetch("title")), " — ", asset.fetch("description") ])
    end
    content_tag(:figure, class: "portfolio-video") do
      safe_join([ content_tag(:video, safe_join(tracks), **options), caption ])
    end
  end

  def next_video_description_id(id)
    @portfolio_video_sequence = @portfolio_video_sequence.to_i + 1
    "portfolio-video-#{id.tr("/", "-")}-#{@portfolio_video_sequence}-description"
  end
end
