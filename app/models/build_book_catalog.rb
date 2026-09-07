require "set"
require "yaml"

class BuildBookCatalog
  class Error < StandardError; end
  class InvalidCatalog < Error; end
  class UnknownEntry < Error; end

  VERSION = 1
  ID_PATTERN = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
  PATH_PATTERN = %r{\A/[a-z0-9]+(?:-[a-z0-9]+)*(?:/[a-z0-9]+(?:-[a-z0-9]+)*)*\z}
  CREDIT_URL_PATTERN = %r{\Ahttps://[a-z0-9.-]+\.[a-z]{2,}(?:/\S*)?\z}i
  BOOK_KEYS = %w[version project_id title kicker byline handle summary path hero_media_id sections].freeze
  SECTION_KEYS = %w[id title lede credit credit_url facts beats].freeze
  FACT_KEYS = %w[label value].freeze
  BEAT_KEYS = %w[text figures].freeze
  FIGURE_KEYS = %w[media_id caption credit credit_url].freeze

  attr_reader :books

  def self.current
    @current ||= new
  end

  def self.reset!
    @current = nil
  end

  def initialize(directory: Rails.root.join("config/build_books"), books: nil, portfolio_catalog: nil, media_catalog: nil)
    loaded = books || load_directory(directory)
    catalog = portfolio_catalog || PortfolioCatalog.current
    media = media_catalog || MediaCatalog.new
    validated = loaded.map { |book| validate_book!(deep_copy(book), catalog, media) }
    @books = deep_freeze(validated)
    @books_by_project_id = index_by_project_id!(@books)
  rescue Psych::Exception, Errno::ENOENT => error
    raise InvalidCatalog, "Could not load build book catalog: #{error.message}"
  end

  def for_project(project_id)
    @books_by_project_id[project_id]
  end

  def build_book!(project_id)
    for_project(project_id) || raise(UnknownEntry, "Unknown build book: #{project_id}")
  end

  def public_paths
    books.pluck("path").freeze
  end

  private

  def index_by_project_id!(books)
    seen = {}
    books.each do |book|
      project_id = book.fetch("project_id")
      if seen.key?(project_id)
        raise InvalidCatalog, "Duplicate build book for project: #{project_id}"
      end
      seen[project_id] = book
    end
    seen.freeze
  end

  def load_directory(directory)
    return [] unless Dir.exist?(directory)

    Dir.glob(File.join(directory, "*.yml")).sort.map do |path|
      YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false)
    end
  end

  def validate_book!(book, catalog, media)
    object!(book, "build book")
    exact_keys!(book, BOOK_KEYS, "build book")
    unless book["version"] == VERSION
      raise InvalidCatalog, "Unsupported build book version: #{book["version"].inspect}"
    end

    project_id = book.fetch("project_id")
    unless project_id.is_a?(String) && ID_PATTERN.match?(project_id)
      raise InvalidCatalog, "Build book has an invalid project id: #{project_id.inspect}"
    end
    catalog.project!(project_id)

    %w[title kicker byline handle summary].each { |key| present_string!(book[key], "build book #{project_id} #{key}") }
    path!(book.fetch("path"), "build book #{project_id} path")
    media.fetch!(book.fetch("hero_media_id"))
    validate_sections!(book.fetch("sections"), project_id, media)
    book
  rescue PortfolioCatalog::UnknownEntry => error
    raise InvalidCatalog, "Build book references an unknown project: #{error.message}"
  rescue MediaCatalog::Error => error
    raise InvalidCatalog, "Build book #{book["project_id"]} references invalid media: #{error.message}"
  end

  def validate_sections!(sections, project_id, media)
    array!(sections, "build book #{project_id} sections")
    raise InvalidCatalog, "Build book #{project_id} has no sections" if sections.empty?

    seen = Set.new
    sections.each do |section|
      object!(section, "build book section")
      exact_keys!(section, SECTION_KEYS, "build book section")
      id = section.fetch("id")
      unless id.is_a?(String) && ID_PATTERN.match?(id)
        raise InvalidCatalog, "Build book #{project_id} has an invalid section id: #{id.inspect}"
      end
      raise InvalidCatalog, "Build book #{project_id} repeats section id: #{id}" unless seen.add?(id)

      present_string!(section["title"], "build book #{project_id} section #{id} title")
      optional_string!(section["lede"], "build book #{project_id} section #{id} lede")
      optional_string!(section["credit"], "build book #{project_id} section #{id} credit")
      credit_url!(section["credit_url"], "build book #{project_id} section #{id} credit url")
      nested_entries!(section["facts"] || [], FACT_KEYS, "build book #{project_id} section #{id} fact")
      validate_beats!(section.fetch("beats"), project_id, id, media)
    end
  end

  def validate_beats!(beats, project_id, section_id, media)
    label = "build book #{project_id} section #{section_id}"
    array!(beats, "#{label} beats")
    raise InvalidCatalog, "#{label.capitalize} has no beats" if beats.empty?

    beats.each do |beat|
      object!(beat, "#{label} beat")
      exact_keys!(beat, BEAT_KEYS, "#{label} beat")
      present_string!(beat["text"], "#{label} beat text")
      figures = beat["figures"] || []
      array!(figures, "#{label} figures")
      figures.each do |figure|
        object!(figure, "#{label} figure")
        exact_keys!(figure, FIGURE_KEYS, "#{label} figure")
        present_string!(figure["caption"], "#{label} figure caption")
        optional_string!(figure["credit"], "#{label} figure credit")
        credit_url!(figure["credit_url"], "#{label} figure credit url")
        media.fetch!(present_string!(figure["media_id"], "#{label} figure media"))
      end
    end
  end

  def nested_entries!(entries, keys, label)
    array!(entries, "#{label}s")
    entries.each do |entry|
      object!(entry, label)
      exact_keys!(entry, keys, label)
      keys.each { |key| present_string!(entry[key], "#{label} #{key}") }
    end
  end

  def exact_keys!(object, keys, label)
    actual = object.keys.sort
    expected = keys.sort
    return if actual == expected

    raise InvalidCatalog, "#{label.capitalize} fields must be #{expected.join(", ")}; got #{actual.join(", ")}"
  end

  def object!(value, label)
    raise InvalidCatalog, "#{label.capitalize} must be an object" unless value.is_a?(Hash)
    value
  end

  def array!(value, label)
    raise InvalidCatalog, "#{label.capitalize} must be an array" unless value.is_a?(Array)
    value
  end

  def present_string!(value, label)
    unless value.is_a?(String) && value.present?
      raise InvalidCatalog, "#{label.capitalize} must be a nonempty string"
    end
    value
  end

  def optional_string!(value, label)
    return if value.nil?
    present_string!(value, label)
  end

  # Credits link off-site, so the scheme is pinned rather than left to the author.
  def credit_url!(value, label)
    return if value.nil?
    unless value.is_a?(String) && CREDIT_URL_PATTERN.match?(value)
      raise InvalidCatalog, "#{label.capitalize} must be an https URL"
    end
    value
  end

  def path!(value, label)
    unless value.is_a?(String) && PATH_PATTERN.match?(value)
      raise InvalidCatalog, "#{label.capitalize} must be a root-relative path"
    end
    value
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end

  def deep_freeze(value)
    case value
    when Hash
      value.each { |key, child| deep_freeze(key); deep_freeze(child) }
    when Array
      value.each { |child| deep_freeze(child) }
    end
    value.freeze
  end
end
