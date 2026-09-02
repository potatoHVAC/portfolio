module MediaManifestFixture
  module_function

  def manifest
    {
      "version" => 1,
      "assets" => {
        "rings/home/hero" => image,
        "videos/studio-tour" => video
      }
    }
  end

  def image
    {
      "kind" => "image",
      "sourceSha256" => "1" * 64,
      "alt" => "Portrait in the studio",
      "width" => 1200,
      "height" => 800,
      "placeholder" => "data:image/jpeg;base64,AA==",
      "sources" => {
        "avif" => image_descriptors("a", "image/avif", "avif"),
        "webp" => image_descriptors("b", "image/webp", "webp"),
        "jpeg" => image_descriptors("c", "image/jpeg", "jpg")
      }
    }
  end

  def video
    {
      "kind" => "video",
      "sourceSha256" => "2" * 64,
      "title" => "Studio tour",
      "description" => "A short walk through the studio",
      "sourceDurationMs" => 95_000,
      "clipStartMs" => 12_500,
      "clipEndMs" => 34_000,
      "durationMs" => 21_500,
      "video" => {
        "path" => "/media/videos/studio-tour/#{"d" * 64}-1280x720.mp4",
        "contentType" => "video/mp4",
        "bytes" => 500_000,
        "width" => 1280,
        "height" => 720
      },
      "poster" => {
        "path" => "/media/videos/studio-tour/#{"e" * 64}-poster.jpg",
        "contentType" => "image/jpeg",
        "bytes" => 50_000,
        "width" => 1280,
        "height" => 720
      },
      "captions" => [
        {
          "path" => "/media/videos/studio-tour/#{"f" * 64}-en-us.vtt",
          "contentType" => "text/vtt; charset=utf-8",
          "bytes" => 500,
          "language" => "en-US",
          "label" => "English"
        }
      ]
    }
  end

  def decorative_image
    image.merge("alt" => "", "decorative" => true)
  end

  def image_descriptors(hash_character, content_type, extension)
    [
      image_descriptor(hash_character, content_type, extension, 480, 320, 10_000),
      image_descriptor(hash_character, content_type, extension, 1200, 800, 30_000)
    ]
  end

  def image_descriptor(hash_character, content_type, extension, width, height, bytes)
    {
      "path" => "/media/rings/home/hero/#{hash_character * 64}-w#{width}.#{extension}",
      "contentType" => content_type,
      "bytes" => bytes,
      "width" => width,
      "height" => height
    }
  end
end
