#!/usr/bin/env ruby

require "http"
require "json"
require "uri"
require "digest"
require "fileutils"
require "active_support/inflector"
require "active_support/core_ext/object/blank"
require "yaml"
require "mini_magick"
require_relative "qr_code_generator"
require_relative "translate"

class GoogleMyMapsDownloader
  attr_reader :valid_features, :page_data, :freguesia_slug, :output_file, :local

  # Image processing configuration
  MAX_IMAGE_WIDTH = 1200
  MAX_IMAGE_HEIGHT = 800
  JPEG_QUALITY = 85

  def initialize(page_data:, freguesia_slug:, verbose: false, local: false)
    @page_data = page_data
    @freguesia_slug = freguesia_slug
    @verbose = verbose
    @local = local

    @output_file = "tmp/#{freguesia_slug}/propostas.geojson"
    @geojson_data = nil
    @valid_features = []
    @non_geo_features = []
    @grouped_propostas = {}
    @downloaded_images = {}
    @images_dir = "assets/data/images"
    @translators = {}
    @should_translate = should_translate?

    setup_translators if @should_translate
  end

  def download_and_process
    validate_requirements
    kml = download_kml
    parse_kml_by_layers(kml)
    tidy_up_features
    group_propostas_by_slug
    download_images
    generate_geojson_from_features
    generate_qr_codes
    generate_jekyll_pages
    generate_propostas_index
    generate_programa_page
    write_final_geojson

    if @should_translate
      generate_translations
    end

    print_summary
  end

  private

  def log(message)
    puts message if @verbose
  end

  def my_google_maps_id
    page_data["my_google_map_id"]
  end

  def should_translate?
    page_data["translation_cache_id"] &&
      page_data["translations"] &&
      page_data["translations"].is_a?(Array) &&
      page_data["translations"].any?
  end

  def setup_translators
    return unless @should_translate

    translation_cache_id = page_data["translation_cache_id"]
    languages = page_data["translations"]

    languages.each do |language|
      log "Setting up translator for language: #{language}"
      @translators[language] = Translate.new(language, translation_cache_id)
    end
  end

  def generate_translations
    return unless @should_translate

    log "Generating translations for languages: #{@translators.keys.join(", ")}"

    @translators.each do |language, translator|
      log "Processing translations for language: #{language}"

      # Generate translated GeoJSON
      generate_translated_geojson(language, translator)

      # Generate translated Jekyll pages
      generate_translated_jekyll_pages(language, translator)

      # Generate translated programa page
      generate_translated_programa_page(language, translator)

      # Generate translated propostas index
      generate_translated_propostas_index(language, translator)
    end

    # Flush all translation caches
    @translators.each { |_, translator| translator.flush_cache }
  end

  def generate_translated_geojson(language, translator)
    return unless @geojson_data

    log "Generating translated GeoJSON for #{language}..."

    translated_geojson = deep_clone(@geojson_data)

    translated_geojson["features"].each do |feature|
      properties = feature["properties"]

      # Translate text properties
      properties.each do |key, value|
        next unless value.is_a?(String)
        next if value.strip.empty?
        next if key == "slug" # Don't translate slugs
        next if key == "gx_media_links" # Don't translate media links
        next if key == "coordinates" # Don't translate coordinates
        next if key == "styleUrl" # Don't translate style URLs
        next if key == "styleHash" # Don't translate style hashes
        next if value.match?(/^https?:\/\//) # Don't translate URLs
        next if value.start_with?("./") # Don't translate file paths
        next if value.match?(/^\d+(\.\d+)?(,\s*\d+(\.\d+)?)*$/) # Don't translate coordinate strings

        translated_value = translator.translate(value)
        properties[key] = translated_value if translated_value
      end
    end

    # Write translated GeoJSON
    output_file = "tmp/#{@freguesia_slug}/propostas-#{language}.geojson"
    File.write(output_file, JSON.pretty_generate(translated_geojson))
    log "Generated translated GeoJSON: #{output_file}"
  end

  def generate_translated_jekyll_pages(language, translator)
    log "Generating translated Jekyll pages for #{language}..."

    generated_count = 0

    @grouped_propostas.each do |slug, group|
      generated_count += 1 if generate_translated_page_for_group(group, language, translator)
    end

    log "Generated #{generated_count} translated Jekyll pages for #{language}"
  end

  def generate_translated_page_for_group(group, language, translator)
    slug = group["slug"]
    return false unless slug && !slug.to_s.strip.empty?

    # Create slug subdirectory for language files
    slug_dir = "#{output_root_path}propostas/#{slug}"
    FileUtils.mkdir_p(slug_dir)

    page_path = "#{slug_dir}/#{language}.md"

    # Generate translated front matter for the group
    front_matter = generate_translated_front_matter_for_group(group, language, translator)

    # Write the page
    File.write(page_path, front_matter)
    log "Generated translated page: #{page_path}"
    true
  end

  def generate_translated_front_matter_for_group(group, language, translator)
    properties = group["combined_properties"]

    # Build front matter hash (start with original)
    front_matter_hash = {
      "layout" => "proposta",
      "freguesia" => translator.translate(page_data["freguesia"]),
      "freguesia_slug" => freguesia_slug,
      "slug" => group["slug"],
      "has_map_location" => group["has_map_location"],
      "parties" => page_data["parties"],
      "under_construction" => page_data["under_construction"],
      "programa_pdf" => page_data["programa_pdf"],
      "language" => language,
      "canonical_slug" => group["slug"] # Keep reference to original
    }

    # Add all combined properties as translated front matter variables
    properties.each do |key, value|
      next if key == "slug" # Already added
      next if ["description", "tessellate", "extrude", "visibility", "coordinates", "styleUrl", "styleHash"].include?(key)
      next if value.nil? || value.to_s.strip.empty?

      # Clean the key name
      clean_key = key.to_s.gsub(/[^a-zA-Z0-9_]/, "_").downcase

      # Translate the value if it's text
      translated_value = if value.to_s.match?(/^https?:\/\//) || value.to_s.start_with?("./")
        # URLs or file paths - don't translate
        value.to_s
      elsif key == "gx_media_links"
        value.to_s
      elsif value.to_s.include?("\n") || value.to_s.length > 10
        # Multi-line or longer text - translate
        translator.translate(value.to_s)
      else
        # Short text - might be a label, translate
        translator.translate(value.to_s)
      end

      front_matter_hash[clean_key] = translated_value
    end

    front_matter_hash["proposta"] ||= front_matter_hash["name"]

    # SEO / Social tags (translated)
    front_matter_hash["title"] = translator.translate(front_matter_hash["proposta"]) if front_matter_hash["proposta"]
    front_matter_hash["description"] = translator.translate(front_matter_hash["sumario"]) if front_matter_hash["sumario"]

    if front_matter_hash["gx_media_links"]
      image_path = front_matter_hash["gx_media_links"].split(" ").first
      front_matter_hash["image"] = if freguesia_slug
        "https://#{freguesia_slug}.viver-lisboa.org#{image_path}"
      else
        "https://www.viver-lisboa.org#{image_path}"
      end
    end

    # Add geometry information (same as original)
    if group["has_map_location"] && group["geographical_features"].any?
      first_geo_feature = group["geographical_features"].first
      geometry = first_geo_feature["geometry"]

      if geometry
        front_matter_hash["geometry"] = {
          "type" => geometry["type"]
        }
        if geometry["coordinates"]
          front_matter_hash["geometry"]["coordinates"] = geometry["coordinates"]
        end
      end

      if group["geographical_features"].length > 1
        front_matter_hash["multiple_locations"] = true
        front_matter_hash["location_count"] = group["geographical_features"].length
      end
    elsif !group["has_map_location"]
      non_geo_with_coords = group["non_geographical_features"].find { |f| f["properties"]["coordinates"] }
      if non_geo_with_coords
        front_matter_hash["reference_coordinates"] = non_geo_with_coords["properties"]["coordinates"]
      end
    end

    # Add feature count information
    front_matter_hash["total_features"] = group["geographical_features"].length + group["non_geographical_features"].length
    front_matter_hash["geographical_features"] = group["geographical_features"].length
    front_matter_hash["non_geographical_features"] = group["non_geographical_features"].length

    # Convert to YAML and build final front matter
    front_matter = front_matter_hash.to_yaml
    front_matter += "---\n\n"
    front_matter += "<!-- This page was automatically generated and translated from Google My Maps data -->\n"
    front_matter += "<!-- Language: #{language} -->\n"
    front_matter += "<!-- To edit this proposal, update the Google My Maps data and re-run the download script -->\n"

    total_features = group["geographical_features"].length + group["non_geographical_features"].length

    if !group["has_map_location"]
      front_matter += "<!-- This proposal does not have a specific map location -->\n"
    elsif group["geographical_features"].length > 1
      front_matter += "<!-- This proposal has #{group["geographical_features"].length} map locations -->\n"
    end
    if total_features > 1
      front_matter += "<!-- This page combines #{total_features} features with the same slug -->\n"
    end

    front_matter
  end

  def generate_translated_programa_page(language, translator)
    return unless page_data["programa_pdf"]

    log "Generating translated programa page for #{language}..."

    # Create programa subdirectory for language files
    programa_dir = "#{output_root_path}programa"
    FileUtils.mkdir_p(programa_dir)

    programa_path = "#{programa_dir}/#{language}.md"

    # Create translated programa page
    front_matter = {
      "layout" => "programa",
      "title" => translator.translate("Programa"),
      "freguesia" => translator.translate(page_data["freguesia"]),
      "freguesia_slug" => freguesia_slug,
      "parties" => page_data["parties"],
      "programa_pdf" => page_data["programa_pdf"],
      "language" => language
    }

    content = front_matter.to_yaml + "---\n\n"
    content += "<!-- This page was automatically generated and translated -->\n"
    content += "<!-- Language: #{language} -->\n"

    File.write(programa_path, content)
    log "Generated translated programa page: #{programa_path}"
  end

  def generate_translated_propostas_index(language, translator)
    log "Generating translated propostas index for #{language}..."

    propostas_dir = "#{output_root_path}propostas"
    FileUtils.mkdir_p(propostas_dir)

    index_path = "#{propostas_dir}/#{language}.html"

    # Build eixo colour map for this context
    eixos = Set.new
    @grouped_propostas.each do |slug, group|
      eixo = group.dig("combined_properties", "eixo")
      eixos << eixo unless eixo.nil?
    end
    eixo_colour_map = build_eixo_colour_map(eixos)

    front_matter = {
      "layout" => "propostas",
      "title" => translator.translate("Propostas"),
      "freguesia" => translator.translate(page_data["freguesia"]),
      "freguesia_slug" => freguesia_slug,
      "parties" => page_data["parties"],
      "under_construction" => page_data["under_construction"],
      "eixo_colours" => eixo_colour_map,
      "language" => language
    }

    content = front_matter.to_yaml + "---\n\n"
    content += "<!-- This page was automatically generated and translated -->\n"
    content += "<!-- Language: #{language} -->\n"

    File.write(index_path, content)
    log "Generated translated propostas index: #{index_path}"
  end

  def deep_clone(obj)
    Marshal.load(Marshal.dump(obj))
  end

  def validate_requirements
    if my_google_maps_id.nil? || my_google_maps_id.empty?
      raise "Google My Maps ID is required"
    end

    # Note: GDAL is no longer required for main processing but can be useful for debugging
    # unless system("which ogr2ogr > /dev/null 2>&1")
    #   raise "GDAL/OGR is required but not found. Install with: brew install gdal (macOS) or apt-get install gdal-bin (Ubuntu)"
    # end

    # Check if http gem is available
    begin
      require "http"
    rescue LoadError
      raise "http gem is required but not found. Install with: bundle install"
    end

    # Ensure tmp directory exists
    FileUtils.mkdir_p("tmp/#{freguesia_slug}") unless Dir.exist?("tmp/#{freguesia_slug}")

    # Ensure images directory exists
    FileUtils.mkdir_p(@images_dir) unless Dir.exist?(@images_dir)

    # Ensure propostas directory exists
    FileUtils.mkdir_p("#{output_root_path}propostas") unless Dir.exist?("#{output_root_path}propostas")
  end

  def download_kml
    raw_kml_path = "tmp/#{freguesia_slug}/raw_data.kml"
    return File.read(raw_kml_path) if local

    url = "https://www.google.com/maps/d/kml?mid=#{my_google_maps_id}&forcekml=1"
    log "Downloading KML from: #{url}"

    begin
      response = HTTP.timeout(30)
        .follow(max_hops: 5)
        .headers(
          "User-Agent" => "Mozilla/5.0 (compatible; Jekyll Map Downloader)",
          "Accept" => "application/vnd.google-earth.kml+xml,application/xml,text/xml,*/*"
        )
        .get(url)

      if response.code != 200
        raise "Failed to download map data (HTTP #{response.code}). Possible issues: map is not publicly accessible, invalid map ID, or network connectivity issues."
      end

      kml_data = response.body.to_s
      log "Downloaded #{kml_data.length} bytes of KML data"

      # Basic validation that we got KML content
      unless kml_data.match?(/<\?xml|<kml/i)
        raise "Downloaded content doesn't appear to be valid KML. Content preview: #{kml_data[0..200]}..."
      end

      # Save raw KML for debugging

      File.write(raw_kml_path, kml_data)
      log "Raw KML saved to #{raw_kml_path}"

      kml_data
    rescue HTTP::Error => e
      raise "HTTP request failed: #{e.message}. This might be due to network connectivity issues, timeout, or Google Maps service issues."
    end
  end

  def parse_kml_by_layers(kml_data)
    log "Parsing KML by layers..."

    require "nokogiri"

    begin
      doc = Nokogiri::XML(kml_data)
      doc.remove_namespaces!

      # Find all folders in the KML
      folders = doc.xpath("//Folder")
      log "Found #{folders.length} folders in KML"

      folders.each do |folder|
        folder_name = folder.xpath("name").text.strip
        placemarks = folder.xpath(".//Placemark")

        log "Processing folder '#{folder_name}' with #{placemarks.length} placemarks"

        if folder_name.include?("Propostas s/ Local") || folder_name.downcase.include?("sem local")
          # This is the non-geographical layer
          process_non_geo_layer(placemarks, folder_name)
        else
          # This is the geographical layer (first layer or default)
          process_geo_layer(placemarks, folder_name)
        end
      end

      # If no folders found, process all placemarks as geographical
      if folders.empty?
        all_placemarks = doc.xpath("//Placemark")
        log "No folders found, processing all #{all_placemarks.length} placemarks as geographical"
        process_geo_layer(all_placemarks, "Default")
      end

      log "Parsing complete: #{@valid_features.length} geographical features, #{@non_geo_features.length} non-geographical features"
    rescue => e
      log "Error parsing KML: #{e.message}"
      raise "Failed to parse KML file: #{e.message}"
    end
  end

  def process_geo_layer(placemarks, folder_name)
    log "Processing geographical layer '#{folder_name}' with #{placemarks.length} placemarks"

    placemarks.each do |placemark|
      feature = extract_feature_from_placemark(placemark, true)
      if feature && validate_feature_geometry(feature)
        @valid_features << feature
      elsif feature
        log "Warning: Placemark '#{feature["properties"]["name"]}' in geographical layer has invalid geometry"
      end
    end
  end

  def process_non_geo_layer(placemarks, folder_name)
    log "Processing non-geographical layer '#{folder_name}' with #{placemarks.length} placemarks"

    placemarks.each do |placemark|
      feature = extract_feature_from_placemark(placemark, false)
      @non_geo_features << feature if feature
    end
  end

  def generate_geojson_from_features
    log "Generating GeoJSON from geographical features with local image paths..."

    # Create GeoJSON structure directly from our parsed features
    # (features should already have local image paths from download_images step)
    @geojson_data = {
      "type" => "FeatureCollection",
      "name" => "#{page_data["title"]} Geographical Features",
      "crs" => {
        "type" => "name",
        "properties" => {
          "name" => "urn:ogc:def:crs:OGC:1.3:CRS84"
        }
      },
      "features" => @valid_features
    }

    log "Generated GeoJSON with #{@valid_features.length} features using local image paths"
  end

  def generate_qr_codes
    return if @valid_features.empty?

    data = @valid_features.map do |feature|
      slug = feature.dig("properties", "slug")
      name = feature.dig("properties", "name")

      next if slug.blank? || name.blank?

      {name: name, url: "https://#{freguesia_slug}.viver-lisboa.org/propostas/#{slug}"}
    end.compact

    return if data.empty?

    QRCodeGenerator.call(data, "#{output_root_path}propostas/qrcodes.pdf")
  end

  def extract_feature_from_placemark(placemark, include_geometry = true)
    name = placemark.xpath("name").text.strip
    description = placemark.xpath("description").text

    # Parse the description to extract structured data
    properties = {"name" => name}

    # Extract key-value pairs from CDATA description
    if description.include?("<br>")
      description.scan(/([^<:]+):\s*([^<]+)(?:<br>|$)/) do |key, value|
        clean_key = key.strip.downcase
        clean_value = value.strip

        # Handle coordinates specially for non-geo features
        if clean_key == "coordenadas" && !include_geometry
          coords = clean_value.split(",").map(&:strip).map(&:to_f)
          if coords.length >= 2
            properties["coordinates"] = coords
          end
        else
          properties[clean_key] = clean_value
        end
      end
    end

    # Also check ExtendedData elements
    placemark.xpath(".//Data").each do |data|
      name_attr = data.attribute("name")&.value
      value_elem = data.xpath("value").text

      if name_attr && !value_elem.empty?
        properties[name_attr.downcase] = value_elem.strip
      end
    end

    # Extract geometry if this is a geographical feature
    geometry = nil
    if include_geometry
      geometry = extract_geometry_from_placemark(placemark)
    end

    # Create GeoJSON feature
    {
      "type" => "Feature",
      "properties" => properties,
      "geometry" => geometry
    }
  rescue => e
    log "Error extracting feature from placemark: #{e.message}"
    nil
  end

  def extract_geometry_from_placemark(placemark)
    # Try to find Point coordinates
    if point = placemark.xpath(".//Point/coordinates").first
      coords_text = point.text.strip
      if coords_text && !coords_text.empty?
        # KML coordinates are in lon,lat,alt format
        coords = coords_text.split(",").map(&:to_f)
        if coords.length >= 2
          return {
            "type" => "Point",
            "coordinates" => coords[0..1]  # Only take lon, lat
          }
        end
      end
    end

    # Try to find LineString coordinates
    if linestring = placemark.xpath(".//LineString/coordinates").first
      coords_text = linestring.text.strip
      if coords_text && !coords_text.empty?
        coordinates = coords_text.split(/\s+/).map do |coord_set|
          coords = coord_set.split(",").map(&:to_f)
          (coords.length >= 2) ? coords[0..1] : nil
        end.compact

        if coordinates.length >= 2
          return {
            "type" => "LineString",
            "coordinates" => coordinates
          }
        end
      end
    end

    # Try to find Polygon coordinates
    if polygon = placemark.xpath(".//Polygon").first
      outer_boundary = polygon.xpath(".//outerBoundaryIs/LinearRing/coordinates").first
      if outer_boundary
        coords_text = outer_boundary.text.strip
        if coords_text && !coords_text.empty?
          coordinates = coords_text.split(/\s+/).map do |coord_set|
            coords = coord_set.split(",").map(&:to_f)
            (coords.length >= 2) ? coords[0..1] : nil
          end.compact

          if coordinates.length >= 4  # Polygon needs at least 4 points
            return {
              "type" => "Polygon",
              "coordinates" => [coordinates]  # Wrap in array for GeoJSON format
            }
          end
        end
      end
    end

    # No valid geometry found
    nil
  rescue => e
    log "Error extracting geometry: #{e.message}"
    nil
  end

  def tidy_up_features
    @valid_features.map! do |feature|
      feature["properties"].transform_keys!(&:downcase)

      feature["properties"] = feature["properties"].slice(
        "slug", "name", "proposta", "sumario", "descricao", "eixo", "gx_media_links"
      )
      feature
    end

    # Also tidy up non-geographical features
    @non_geo_features.map! do |feature|
      feature["properties"].transform_keys!(&:downcase)

      feature["properties"] = feature["properties"].slice(
        "slug", "name", "proposta", "sumario", "descricao", "eixo", "coordinates", "gx_media_links"
      )
      feature
    end
  end

  def group_propostas_by_slug
    log "Grouping propostas by slug..."

    @grouped_propostas = {}

    # Process geographical features
    @valid_features.each do |feature|
      slug = feature["properties"]["slug"]
      next unless slug && !slug.to_s.strip.empty?

      slug = slug.to_s.strip
      @grouped_propostas[slug] ||= {
        "slug" => slug,
        "has_map_location" => false,
        "geographical_features" => [],
        "non_geographical_features" => [],
        "combined_properties" => {},
        "all_images" => []
      }

      @grouped_propostas[slug]["has_map_location"] = true
      @grouped_propostas[slug]["geographical_features"] << feature
      merge_properties(@grouped_propostas[slug], feature["properties"])
    end

    # Process non-geographical features
    @non_geo_features.each do |feature|
      slug = feature["properties"]["slug"]
      next unless slug && !slug.to_s.strip.empty?

      slug = slug.to_s.strip
      @grouped_propostas[slug] ||= {
        "slug" => slug,
        "has_map_location" => false,
        "geographical_features" => [],
        "non_geographical_features" => [],
        "combined_properties" => {},
        "all_images" => []
      }

      @grouped_propostas[slug]["non_geographical_features"] << feature
      merge_properties(@grouped_propostas[slug], feature["properties"])
    end

    log "Grouped #{@valid_features.length + @non_geo_features.length} features into #{@grouped_propostas.length} unique propostas"
  end

  def merge_properties(group, properties)
    # Collect images from all features
    if properties["gx_media_links"] && !properties["gx_media_links"].to_s.strip.empty?
      images = properties["gx_media_links"].to_s.split(/[\s,]+/).reject(&:empty?)
      group["all_images"].concat(images)
    end

    # Merge other properties (prefer non-empty values)
    properties.each do |key, value|
      next if key == "gx_media_links" # Handle images separately
      next if value.nil? || value.to_s.strip.empty?

      if group["combined_properties"][key].nil? || group["combined_properties"][key].to_s.strip.empty?
        group["combined_properties"][key] = value
      elsif group["combined_properties"][key] != value && !value.to_s.strip.empty?
        # If values differ, append the new value
        case key
        when "descricao", "sumario"
          # For descriptions, combine with line breaks
          existing = group["combined_properties"][key].to_s
          unless existing.include?(value.to_s)
            group["combined_properties"][key] = "#{existing}\n\n#{value}"
          end
        else
          # For other fields, prefer the existing value but log the difference
          log "Different values for #{key} in slug #{group["slug"]}: keeping '#{group["combined_properties"][key]}', ignoring '#{value}'"
        end
      end
    end

    # Remove duplicates and empty images
    group["all_images"].uniq!
    group["all_images"].reject! { |img| img.nil? || img.to_s.strip.empty? }
  end

  def download_images
    return if local
    log "Processing images from grouped propostas..."

    image_count = 0

    @grouped_propostas.each do |slug, group|
      next if group["all_images"].empty?

      downloaded_urls = []
      group["all_images"].each do |url|
        local_path = download_single_image(url)
        if local_path
          downloaded_urls << local_path
          image_count += 1
        end
      rescue => e
        log "Failed to download image #{url}: #{e.message}"
      end

      # Update the group with downloaded image paths (combined for Jekyll pages)
      if downloaded_urls.any?
        group["combined_properties"]["gx_media_links"] = downloaded_urls.join(" ")
      end

      # Update individual features with their own downloaded images (for GeoJSON)
      update_individual_features_with_local_images(group, downloaded_urls)
    end

    log "Downloaded #{image_count} images to #{@images_dir}/"
  end

  def update_individual_features_with_local_images(group, all_downloaded_urls)
    # Create a mapping of original URLs to local paths
    url_mapping = {}
    group["all_images"].each_with_index do |original_url, index|
      if index < all_downloaded_urls.length
        url_mapping[original_url] = all_downloaded_urls[index]
      end
    end

    # Update geographical features with their individual images
    group["geographical_features"].each do |feature|
      original_links = feature["properties"]["gx_media_links"]
      next unless original_links

      # Convert original URLs to local paths for this specific feature
      original_urls = original_links.split(/[\s,]+/).reject(&:empty?)
      local_urls = original_urls.map { |url| url_mapping[url] }.compact

      if local_urls.any?
        # Find the actual feature in @valid_features and update it
        @valid_features.each do |valid_feature|
          if valid_feature.equal?(feature)
            valid_feature["properties"]["gx_media_links"] = local_urls.join(" ")
            break
          end
        end
      else
        # Remove gx_media_links if no local images
        @valid_features.each do |valid_feature|
          if valid_feature.equal?(feature)
            valid_feature["properties"].delete("gx_media_links")
            break
          end
        end
      end
    end

    # Update non-geographical features with their individual images
    group["non_geographical_features"].each do |feature|
      original_links = feature["properties"]["gx_media_links"]
      next unless original_links

      # Convert original URLs to local paths for this specific feature
      original_urls = original_links.split(/[\s,]+/).reject(&:empty?)
      local_urls = original_urls.map { |url| url_mapping[url] }.compact

      if local_urls.any?
        feature["properties"]["gx_media_links"] = local_urls.join(" ")
      else
        feature["properties"].delete("gx_media_links")
      end
    end
  end

  def generate_jekyll_pages
    log "Generating Jekyll pages for grouped propostas..."

    generated_count = 0

    @grouped_propostas.each do |slug, group|
      generated_count += 1 if generate_page_for_group(group)
    end

    log "Generated #{generated_count} Jekyll pages total"
  end

  def generate_page_for_group(group)
    slug = group["slug"]
    return false unless slug && !slug.to_s.strip.empty?

    page_path = "#{output_root_path}propostas/#{slug}.md"

    # Create directory if it doesn't exist
    FileUtils.mkdir_p(File.dirname(page_path))

    # Generate front matter for the group
    front_matter = generate_front_matter_for_group(group)

    # Write the page
    File.write(page_path, front_matter)
    log "Generated page: #{page_path} (#{group["has_map_location"] ? "with" : "without"} map location, #{group["geographical_features"].length + group["non_geographical_features"].length} features)"
    true
  end

  def generate_front_matter_for_group(group)
    properties = group["combined_properties"]

    # Build front matter hash
    front_matter_hash = {
      "layout" => "proposta",
      "freguesia" => page_data["freguesia"],
      "freguesia_slug" => freguesia_slug,
      "slug" => group["slug"],
      "has_map_location" => group["has_map_location"],
      "parties" => page_data["parties"],
      "under_construction" => page_data["under_construction"],
      "programa_pdf" => page_data["programa_pdf"]
    }

    # Add all combined properties as front matter variables
    properties.each do |key, value|
      next if key == "slug" # Already added
      next if ["description", "tessellate", "extrude", "visibility", "coordinates"].include?(key) # fields to ignore or handle separately
      next if value.nil? || value.to_s.strip.empty?

      # Clean the key name
      clean_key = key.to_s.gsub(/[^a-zA-Z0-9_]/, "_").downcase

      # Handle different value types
      front_matter_hash[clean_key] = if value.to_s.include?("\n")
        # Multi-line content - YAML will handle this automatically
        value.to_s
      elsif value.to_s.match?(/^https?:\/\//) || value.to_s.start_with?("./")
        # URLs or file paths
        value.to_s
      else
        # Regular content
        value
      end
    end

    front_matter_hash["proposta"] ||= front_matter_hash["name"]

    # SEO / Social tags
    front_matter_hash["title"] = front_matter_hash["proposta"]
    front_matter_hash["description"] = front_matter_hash["sumario"]
    if front_matter_hash["gx_media_links"]
      image_path = front_matter_hash["gx_media_links"].split(" ").first
      front_matter_hash["image"] = if freguesia_slug
        "https://#{freguesia_slug}.viver-lisboa.org#{image_path}"
      else
        "https://www.viver-lisboa.org#{image_path}"
      end
    end

    # Add geometry information from geographical features
    if group["has_map_location"] && group["geographical_features"].any?
      # Use the first geographical feature's geometry
      first_geo_feature = group["geographical_features"].first
      geometry = first_geo_feature["geometry"]

      if geometry
        front_matter_hash["geometry"] = {
          "type" => geometry["type"]
        }
        if geometry["coordinates"]
          front_matter_hash["geometry"]["coordinates"] = geometry["coordinates"]
        end
      end

      # If there are multiple geographical features, note this
      if group["geographical_features"].length > 1
        front_matter_hash["multiple_locations"] = true
        front_matter_hash["location_count"] = group["geographical_features"].length
      end
    elsif !group["has_map_location"]
      # For non-geo features, check if any have reference coordinates
      non_geo_with_coords = group["non_geographical_features"].find { |f| f["properties"]["coordinates"] }
      if non_geo_with_coords
        front_matter_hash["reference_coordinates"] = non_geo_with_coords["properties"]["coordinates"]
      end
    end

    # Add feature count information
    front_matter_hash["total_features"] = group["geographical_features"].length + group["non_geographical_features"].length
    front_matter_hash["geographical_features"] = group["geographical_features"].length
    front_matter_hash["non_geographical_features"] = group["non_geographical_features"].length

    # Convert to YAML and build final front matter
    front_matter = front_matter_hash.to_yaml
    front_matter += "---\n\n"
    front_matter += "<!-- This page was automatically generated from Google My Maps data -->\n"
    front_matter += "<!-- To edit this proposal, update the Google My Maps data and re-run the download script -->\n"
    # Calculate total features before using it
    total_features = group["geographical_features"].length + group["non_geographical_features"].length

    if !group["has_map_location"]
      front_matter += "<!-- This proposal does not have a specific map location -->\n"
    elsif group["geographical_features"].length > 1
      front_matter += "<!-- This proposal has #{group["geographical_features"].length} map locations -->\n"
    end
    if total_features > 1
      front_matter += "<!-- This page combines #{total_features} features with the same slug -->\n"
    end

    front_matter
  end

  def generate_propostas_index
    log "Generating #{freguesia_slug} propostas index page..."

    eixos = Set.new
    @grouped_propostas.each do |slug, group|
      eixo = group.dig("combined_properties", "eixo")
      eixos << eixo unless eixo.nil?
    end
    eixos_colour_map = build_eixo_colour_map(eixos)

    # Generate the index page content
    front_matter = {
      "layout" => "propostas",
      "freguesia_slug" => freguesia_slug,
      "freguesia" => page_data["freguesia"],
      "parties" => page_data["parties"],
      "title" => "Todas as Propostas",
      "description" => "Explore todas as propostas da coligação Viver Lisboa #{page_data["freguesia"]} para as Eleições Autárquicas 2025",
      "under_construction" => page_data["under_construction"],
      "eixos" => eixos.sort,
      "eixos_colour_map" => eixos_colour_map,
      "programa_pdf" => page_data["programa_pdf"]
    }
    index_content = <<~FRONTMATTER
      #{front_matter.to_yaml}
      ---

    FRONTMATTER

    # Write the index page
    File.write("#{output_root_path}propostas/index.md", index_content)
  end

  def build_eixo_colour_map(eixos)
    colours = YAML.load_file("_data/eixo_colors.yml")["colors"]
    unmatched_eixos = eixos.dup

    result = {}
    eixos.each do |eixo|
      colour = colours.detect { |c| c["eixos"].include? eixo }

      if colour
        result[eixo] = {
          "color" => colour["hex"],
          "className" => colour["name"]
        }
        unmatched_eixos.delete(eixo)
        colours.delete(colour)
      end
    end

    unmatched_eixos.each_with_index do |eixo, index|
      # Distribute colors evenly across the available color array
      color_index = (index * colours.length / unmatched_eixos.length).to_i
      colour = colours[color_index]
      if colour
        result[eixo] = {
          "color" => colour["hex"],
          "className" => colour["name"]
        }
      end
    end

    result
  end

  def generate_programa_page
    # Only generate if programa_pdf is present
    return unless page_data["programa_pdf"] && !page_data["programa_pdf"].to_s.strip.empty?

    log "Generating #{freguesia_slug} programa page..."

    # Generate the programa page content
    front_matter = {
      "layout" => "programa",
      "freguesia_slug" => freguesia_slug,
      "freguesia" => page_data["freguesia"],
      "parties" => page_data["parties"],
      "title" => "Programa Completo",
      "description" => "Descarregue o programa completo da coligação Viver Lisboa: #{page_data["freguesia"]} para as Eleições Autárquicas 2025",
      "under_construction" => page_data["under_construction"],
      "programa_pdf" => page_data["programa_pdf"]
    }

    programa_content = <<~FRONTMATTER
      #{front_matter.to_yaml}
      ---

    FRONTMATTER

    # Write the programa page
    File.write("#{output_root_path}programa.md", programa_content)
    log "Generated programa page: #{output_root_path}programa.md"
  end

  def escape_html(text)
    return "" if text.nil?
    text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;").gsub("'", "&#39;")
  end

  def download_single_image(url)
    return nil unless url.match?(/^https?:\/\//)

    # Create a unique filename based on URL hash
    url_hash = Digest::MD5.hexdigest(url)[0..8]
    extension = extract_file_extension(url)
    filename = "#{freguesia_slug}_#{url_hash}#{extension}"
    local_path = File.join(@images_dir, filename)
    image_url_path = "/#{local_path}"

    # Skip if already downloaded
    if @downloaded_images[url]
      return @downloaded_images[url]
    end

    # Skip if file already exists (check both original extension and .jpg)
    jpeg_filename = filename.gsub(/\.\w+$/, ".jpg")
    jpeg_local_path = File.join(@images_dir, jpeg_filename)
    jpeg_image_url_path = "/#{jpeg_local_path}"

    if File.exist?(local_path)
      log "Image already exists: #{filename}"
      @downloaded_images[url] = image_url_path
      return image_url_path
    elsif File.exist?(jpeg_local_path)
      log "Image already exists (as JPEG): #{jpeg_filename}"
      @downloaded_images[url] = jpeg_image_url_path
      return jpeg_image_url_path
    end

    log "Downloading image: #{url} -> #{filename}"

    response = HTTP.timeout(30)
      .follow(max_hops: 3)
      .headers(
        "User-Agent" => "Mozilla/5.0 (compatible; Jekyll Map Downloader)",
        "Accept" => "image/*,*/*"
      )
      .get(url)

    if response.code == 200
      # Validate it's actually an image
      content_type = response.headers["Content-Type"].to_s
      unless content_type.start_with?("image/")
        log "Warning: #{url} doesn't appear to be an image (Content-Type: #{content_type})"
      end

      # Write original image to temporary file
      temp_path = "#{local_path}.tmp"
      body_content = response.body.to_s
      File.write(temp_path, body_content)

      # Process image for web optimization
      begin
        image = MiniMagick::Image.open(temp_path)
        original_size = image.size

        # Resize if too large
        if image.width > MAX_IMAGE_WIDTH || image.height > MAX_IMAGE_HEIGHT
          image.resize "#{MAX_IMAGE_WIDTH}x#{MAX_IMAGE_HEIGHT}>"
          log "Resized image from #{original_size[0]}x#{original_size[1]} to #{image.width}x#{image.height}"
        end

        # Set quality for JPEG compression
        image.quality JPEG_QUALITY

        # Convert to JPEG if it's not already (for better compression)
        if image.type != "JPEG"
          # Update filename extension to .jpg
          new_filename = filename.gsub(/\.\w+$/, ".jpg")
          new_local_path = File.join(@images_dir, new_filename)
          new_image_url_path = "/#{new_local_path}"

          image.format "jpeg"
          image.write(new_local_path)

          # Clean up temp file
          File.delete(temp_path) if File.exist?(temp_path)

          @downloaded_images[url] = new_image_url_path
          log "Successfully processed and converted: #{new_filename} (#{format_file_size(File.size(new_local_path))})"
          new_image_url_path
        else
          image.write(local_path)

          # Clean up temp file
          File.delete(temp_path) if File.exist?(temp_path)

          @downloaded_images[url] = image_url_path
          log "Successfully processed: #{filename} (#{format_file_size(File.size(local_path))})"
          image_url_path
        end
      rescue MiniMagick::Error => e
        log "Failed to process image #{filename}: #{e.message}. Saving original."
        # Fallback: save original if processing fails
        File.rename(temp_path, local_path) if File.exist?(temp_path)
        @downloaded_images[url] = image_url_path
        log "Successfully downloaded (unprocessed): #{filename} (#{format_file_size(body_content.length)})"
        image_url_path
      end
    else
      log "Failed to download #{url}: HTTP #{response.code}"
      nil
    end
  rescue => e
    log "Error downloading #{url}: #{e.message}"
    nil
  end

  def extract_file_extension(url)
    # Try to get extension from URL path
    uri = URI.parse(url)
    path = uri.path.to_s

    # Common image extensions
    if path.match?(/\.(jpe?g|png|gif|webp|bmp|svg)$/i)
      extension = path.match(/(\.[^.]+)$/)[1].downcase
      return extension
    end

    # Default to .jpg if no extension found
    ".jpg"
  rescue
    ".jpg"
  end

  def write_final_geojson
    log "Writing final GeoJSON file..."

    # Create the final GeoJSON structure
    final_geojson = {
      "type" => "FeatureCollection",
      "name" => "#{page_data["title"]} Layer (#{my_google_maps_id})",
      "crs" => {
        "type" => "name",
        "properties" => {
          "name" => "urn:ogc:def:crs:OGC:1.3:CRS84"
        }
      },
      "features" => @valid_features
    }

    # Write the final GeoJSON file
    File.write(@output_file, JSON.pretty_generate(final_geojson))
    log "Saved final GeoJSON to #{@output_file}"
  end

  def validate_feature_geometry(feature)
    geometry = feature["geometry"]
    return false if geometry.nil? || geometry["coordinates"].nil?

    case geometry["type"]
    when "Point"
      validate_point_coordinates(geometry["coordinates"])
    when "LineString"
      validate_linestring_coordinates(geometry["coordinates"])
    when "Polygon"
      validate_polygon_coordinates(geometry["coordinates"])
    when "MultiPoint"
      geometry["coordinates"].all? { |coords| validate_point_coordinates(coords) }
    when "MultiLineString"
      geometry["coordinates"].all? { |coords| validate_linestring_coordinates(coords) }
    when "MultiPolygon"
      geometry["coordinates"].all? { |coords| validate_polygon_coordinates(coords) }
    else
      false
    end
  end

  def validate_point_coordinates(coords)
    coords.is_a?(Array) && coords.length >= 2 &&
      coords[0].is_a?(Numeric) && coords[1].is_a?(Numeric) &&
      coords[0].between?(-180, 180) && coords[1].between?(-90, 90)
  end

  def validate_linestring_coordinates(coords)
    coords.is_a?(Array) && coords.length >= 2 &&
      coords.all? { |point| validate_point_coordinates(point) }
  end

  def validate_polygon_coordinates(coords)
    coords.is_a?(Array) && coords.all? do |ring|
      ring.is_a?(Array) && ring.length >= 4 &&
        ring.all? { |point| validate_point_coordinates(point) } &&
        ring.first == ring.last  # Ensure ring is closed
    end
  end

  def print_summary
    file_size = File.size(@output_file)
    puts "✅ Successfully processed Google My Maps data!"
    puts "   📍 Map ID: #{my_google_maps_id}"
    puts "   📊 Valid features: #{@valid_features.length}"
    puts "   🖼️  Downloaded images: #{@downloaded_images.length}"

    # Count generated pages and features
    total_generated_pages = @grouped_propostas.length
    pages_with_location = @grouped_propostas.count { |slug, group| group["has_map_location"] }
    pages_without_location = total_generated_pages - pages_with_location
    total_features = @valid_features.length + @non_geo_features.length
    puts "   📄 Generated pages: #{total_generated_pages} (#{pages_with_location} with location, #{pages_without_location} without location)"
    puts "   🔗 Total features: #{total_features} (grouped into #{total_generated_pages} unique propostas by slug)"

    puts "   💾 File size: #{format_file_size(file_size)}"
    puts "   📁 Output: #{@output_file}"
    puts "   🖼️  Images folder: #{@images_dir}/"
    puts "   📄 Pages folder: propostas/"

    # Show feature type breakdown
    feature_types = @valid_features.group_by { |f| f["geometry"]["type"] }
    feature_types.each do |type, features|
      puts "   └─ #{type}: #{features.length} features"
    end

    # Show features with images
    features_with_images = @valid_features.count { |f| f["properties"] && f["properties"]["gx_media_links"] }
    if features_with_images > 0
      puts "   └─ Features with images: #{features_with_images}"
    end

    # Show non-geographical features summary
    if @non_geo_features.length > 0
      puts "   └─ Non-geographical proposals: #{@non_geo_features.length}"
    end

    # Show programa page generation
    if page_data["programa_pdf"] && !page_data["programa_pdf"].to_s.strip.empty?
      puts "   └─ Generated programa page with PDF: #{page_data["programa_pdf"]}"
    end
  end

  def format_file_size(bytes)
    if bytes < 1024
      "#{bytes} bytes"
    elsif bytes < 1024 * 1024
      "#{(bytes / 1024.0).round(1)} KB"
    else
      "#{(bytes / (1024.0 * 1024)).round(1)} MB"
    end
  end

  def output_root_path
    if freguesia_slug.nil?
      ""
    else
      "freguesias/#{freguesia_slug}/"
    end
  end
end
