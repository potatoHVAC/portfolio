require "set"
require "yaml"

class PortfolioCatalog
  class Error < StandardError; end
  class InvalidCatalog < Error; end
  class UnknownEntry < Error; end

  VERSION = 1
  ID_PATTERN = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
  PATH_PATTERN = %r{\A/[a-z0-9]+(?:-[a-z0-9]+)*(?:/[a-z0-9]+(?:-[a-z0-9]+)*)*\z}
  ROOT_KEYS = %w[version site sections projects galleries].freeze
  SITE_KEYS = %w[name shop tagline manifesto invitation description].freeze
  ACCENTS = %w[electric spectacle ember].freeze
  SECTION_KEYS = %w[id title eyebrow summary path accent featured_project_ids].freeze
  PROJECT_KEYS = %w[id section_id title kicker summary path hero_media_id feature_media_id gallery_id facts stories].freeze
  GALLERY_KEYS = %w[id section_id title summary path status cover_media_id media_ids].freeze
  FACT_KEYS = %w[label value].freeze
  STORY_KEYS = %w[heading body].freeze
  CORE_PATHS = %w[/ /galleries /about /contact].freeze

  attr_reader :site, :sections, :projects, :galleries

  def self.current
    @current ||= new
  end

  def self.reset!
    @current = nil
  end

  def initialize(path: Rails.root.join("config/portfolio.yml"), catalog: nil, media_catalog: nil)
    data = catalog || YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false)
    validated = validate_catalog!(deep_copy(data), media_catalog || MediaCatalog.new)
    @site = deep_freeze(validated.fetch("site"))
    @sections = deep_freeze(validated.fetch("sections"))
    @projects = deep_freeze(validated.fetch("projects"))
    @galleries = deep_freeze(validated.fetch("galleries"))
    @sections_by_id = sections.index_by { |entry| entry.fetch("id") }.freeze
    @projects_by_id = projects.index_by { |entry| entry.fetch("id") }.freeze
    @galleries_by_id = galleries.index_by { |entry| entry.fetch("id") }.freeze
  rescue Psych::Exception, Errno::ENOENT => error
    raise InvalidCatalog, "Could not load portfolio catalog: #{error.message}"
  end

  def section!(id)
    @sections_by_id[id] || raise(UnknownEntry, "Unknown portfolio section: #{id}")
  end

  def project!(id)
    @projects_by_id[id] || raise(UnknownEntry, "Unknown portfolio project: #{id}")
  end

  def gallery!(id)
    @galleries_by_id[id] || raise(UnknownEntry, "Unknown portfolio gallery: #{id}")
  end

  def projects_for(section_id)
    projects.select { |entry| entry.fetch("section_id") == section_id }
  end

  def galleries_for(section_id)
    galleries.select { |entry| entry.fetch("section_id") == section_id }
  end

  def unsectioned_galleries
    galleries.reject { |entry| entry["section_id"] }
  end

  def featured_projects_for(section_id)
    section!(section_id).fetch("featured_project_ids").map { |id| project!(id) }
  end

  def public_paths
    (CORE_PATHS + sections.pluck("path") + projects.pluck("path") + galleries.pluck("path")).uniq.freeze
  end

  private

  def validate_catalog!(catalog, media_catalog)
    object!(catalog, "catalog")
    exact_keys!(catalog, ROOT_KEYS, "catalog")
    unless catalog["version"] == VERSION
      raise InvalidCatalog, "Unsupported portfolio catalog version: #{catalog["version"].inspect}"
    end

    validate_site!(catalog.fetch("site"))
    validate_entries!(catalog.fetch("sections"), SECTION_KEYS, "section") { |entry| validate_section!(entry) }
    validate_entries!(catalog.fetch("projects"), PROJECT_KEYS, "project") { |entry| validate_project!(entry) }
    validate_entries!(catalog.fetch("galleries"), GALLERY_KEYS, "gallery") do |entry|
      validate_gallery!(entry, media_catalog)
    end
    validate_relationships!(catalog)
    validate_unique_paths!(catalog)
    catalog
  end

  def validate_site!(site)
    object!(site, "site")
    exact_keys!(site, SITE_KEYS, "site")
    SITE_KEYS.each { |key| present_string!(site[key], "site #{key}") }
  end

  def validate_entries!(entries, keys, label)
    array!(entries, "#{label}s")
    seen = Set.new
    entries.each do |entry|
      object!(entry, label)
      exact_keys!(entry, keys, label)
      id = entry.fetch("id")
      unless id.is_a?(String) && ID_PATTERN.match?(id)
        raise InvalidCatalog, "#{label.capitalize} has an invalid id: #{id.inspect}"
      end
      raise InvalidCatalog, "Duplicate #{label} id: #{id}" unless seen.add?(id)

      yield entry
    end
  end

  def validate_section!(section)
    %w[title eyebrow summary accent].each do |key|
      present_string!(section[key], "section #{section["id"]} #{key}")
    end
    unless ACCENTS.include?(section.fetch("accent"))
      raise InvalidCatalog, "Section #{section["id"]} accent must be one of #{ACCENTS.join(", ")}"
    end
    path!(section.fetch("path"), "section #{section["id"]} path")
    string_array!(section.fetch("featured_project_ids"), "section #{section["id"]} featured projects")
  end

  def validate_project!(project)
    %w[section_id title kicker summary gallery_id].each do |key|
      present_string!(project[key], "project #{project["id"]} #{key}")
    end
    path!(project.fetch("path"), "project #{project["id"]} path")
    optional_string!(project["hero_media_id"], "project #{project["id"]} hero media")
    optional_string!(project["feature_media_id"], "project #{project["id"]} feature media")
    nested_entries!(project.fetch("facts"), FACT_KEYS, "project #{project["id"]} fact")
    nested_entries!(project.fetch("stories"), STORY_KEYS, "project #{project["id"]} story")
  end

  def validate_gallery!(gallery, media_catalog)
    %w[title summary path status].each do |key|
      present_string!(gallery[key], "gallery #{gallery["id"]} #{key}")
    end
    optional_string!(gallery["section_id"], "gallery #{gallery["id"]} section")
    path!(gallery.fetch("path"), "gallery #{gallery["id"]} path")
    optional_string!(gallery["cover_media_id"], "gallery #{gallery["id"]} cover media")
    media_ids = string_array!(gallery.fetch("media_ids"), "gallery #{gallery["id"]} media")
    raise InvalidCatalog, "Gallery #{gallery["id"]} repeats a media id" unless media_ids.uniq.size == media_ids.size

    referenced_media = media_ids + [ gallery["cover_media_id"] ].compact
    referenced_media.each { |id| media_catalog.fetch!(id) }
    if gallery["cover_media_id"] && !media_ids.include?(gallery["cover_media_id"])
      raise InvalidCatalog, "Gallery #{gallery["id"]} cover must be included in its media"
    end
  rescue MediaCatalog::Error => error
    raise InvalidCatalog, "Gallery #{gallery["id"]} references invalid media: #{error.message}"
  end

  def validate_relationships!(catalog)
    sections = catalog.fetch("sections").index_by { |entry| entry.fetch("id") }
    projects = catalog.fetch("projects").index_by { |entry| entry.fetch("id") }
    galleries = catalog.fetch("galleries").index_by { |entry| entry.fetch("id") }

    catalog.fetch("projects").each do |project|
      section_id = project.fetch("section_id")
      raise InvalidCatalog, "Project #{project["id"]} has an unknown section" unless sections.key?(section_id)

      gallery = galleries[project.fetch("gallery_id")]
      unless gallery && gallery.fetch("section_id") == section_id
        raise InvalidCatalog, "Project #{project["id"]} has an invalid gallery"
      end
    end

    catalog.fetch("galleries").each do |gallery|
      section_id = gallery["section_id"]
      next if section_id.nil?
      unless sections.key?(section_id)
        raise InvalidCatalog, "Gallery #{gallery["id"]} has an unknown section"
      end
    end

    catalog.fetch("sections").each do |section|
      section.fetch("featured_project_ids").each do |project_id|
        project = projects[project_id]
        unless project && project.fetch("section_id") == section.fetch("id")
          raise InvalidCatalog, "Section #{section["id"]} has an invalid featured project"
        end
      end
    end
  end

  def validate_unique_paths!(catalog)
    paths = CORE_PATHS + catalog.fetch("sections").pluck("path") +
      catalog.fetch("projects").pluck("path") + catalog.fetch("galleries").pluck("path")
    duplicate = paths.tally.find { |_path, count| count > 1 }&.first
    raise InvalidCatalog, "Duplicate portfolio path: #{duplicate}" if duplicate
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

  def string_array!(value, label)
    array!(value, label)
    value.each { |item| present_string!(item, label) }
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
