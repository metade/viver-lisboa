#!/usr/bin/env ruby

require "http"
require "json"
require "uri"
require "digest"
require "fileutils"
require "active_support/inflector"
require "yaml"
require "mini_magick"

class GoogleMyMapsDownloader
  attr_reader :valid_features, :page_data, :freguesia_slug, :output_file

  # Image processing configuration
  MAX_IMAGE_WIDTH = 1200
  MAX_IMAGE_HEIGHT = 800
  JPEG_QUALITY = 85

  def initialize(page_data:, freguesia_slug:, verbose: false)
    @verbose = verbose
    @freguesia_slug = freguesia_slug
    @output_file = "tmp/#{freguesia_slug}/propostas.geojson"
    @page_data = page_data
    @kml_data = nil
    @geojson_data = nil
    @valid_features = []
    @non_geo_features = []
    @downloaded_images = {}
    @images_dir = "assets/data/images"
  end

  def download_and_process
    validate_requirements
    download_kml
    convert_to_geojson
    filter_features
    extract_non_geo_features
    tidy_up_features
    download_images
    generate_jekyll_pages
    generate_propostas_index
    write_final_geojson
    cleanup
    print_summary
  end

  private

  def log(message)
    puts message if @verbose
  end

  def my_google_maps_id
    page_data["my_google_map_id"]
  end

  def validate_requirements
    if my_google_maps_id.nil? || my_google_maps_id.empty?
      raise "Google My Maps ID is required"
    end

    # Check if GDAL is available
    unless system("which ogr2ogr > /dev/null 2>&1")
      raise "GDAL/OGR is required but not found. Install with: brew install gdal (macOS) or apt-get install gdal-bin (Ubuntu)"
    end

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
    FileUtils.mkdir_p("freguesias/#{freguesia_slug}/propostas") unless Dir.exist?("freguesias/#{freguesia_slug}/propostas")
  end

  def download_kml
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

      @kml_data = response.body.to_s
      log "Downloaded #{@kml_data.length} bytes of KML data"

      # Basic validation that we got KML content
      unless @kml_data.match?(/<\?xml|<kml/i)
        raise "Downloaded content doesn't appear to be valid KML. Content preview: #{@kml_data[0..200]}..."
      end

      # Save raw KML for debugging
      File.write("tmp/raw_data.kml", @kml_data)
      log "Raw KML saved to tmp/raw_data.kml"
    rescue HTTP::Error => e
      raise "HTTP request failed: #{e.message}. This might be due to network connectivity issues, timeout, or Google Maps service issues."
    end
  end

  def convert_to_geojson
    log "Converting KML to GeoJSON using ogr2ogr..."

    # Use -skipfailures to handle multiple layers gracefully
    # This allows ogr2ogr to skip layers that can't be converted instead of failing entirely
    conversion_success = system("ogr2ogr -f GeoJSON -skipfailures tmp/temp_data.geojson tmp/raw_data.kml 2>/dev/null")

    unless conversion_success && File.exist?("tmp/temp_data.geojson")
      # If it still fails, try without error suppression to see what's wrong
      log "Conversion failed, retrying without error suppression for debugging..."
      system("ogr2ogr -f GeoJSON -skipfailures tmp/temp_data.geojson tmp/raw_data.kml")
      raise "Failed to convert KML to GeoJSON. This might happen if the KML file is empty/corrupted or there are GDAL version compatibility issues."
    end

    @geojson_data = JSON.parse(File.read("tmp/temp_data.geojson"))
    log "Converted to GeoJSON with #{@geojson_data["features"].length} features"
  end

  def filter_features
    log "Filtering features for valid coordinates..."

    @valid_features = @geojson_data["features"].select do |feature|
      validate_feature_geometry(feature)
    end

    log "Filtered #{@geojson_data["features"].length} features down to #{@valid_features.length} valid features"
  end

  def extract_non_geo_features
    log "Extracting proposals without locations from KML..."

    # Parse the KML to find features in "Propostas s/ Local" folder
    require "nokogiri"

    begin
      doc = Nokogiri::XML(@kml_data)
      doc.remove_namespaces!

      # Find the "Propostas s/ Local" folder
      folders = doc.xpath("//Folder")
      non_geo_folder = folders.find { |folder| folder.xpath("name").text.include?("Propostas s/ Local") }

      if non_geo_folder
        placemarks = non_geo_folder.xpath(".//Placemark")
        log "Found #{placemarks.length} proposals without locations"

        placemarks.each do |placemark|
          feature = extract_feature_from_placemark(placemark)
          @non_geo_features << feature if feature
        end

        log "Extracted #{@non_geo_features.length} non-geographical proposals"
      else
        log "No 'Propostas s/ Local' folder found"
      end
    rescue => e
      log "Error parsing KML for non-geographical features: #{e.message}"
    end
  end

  def extract_feature_from_placemark(placemark)
    name = placemark.xpath("name").text.strip
    description = placemark.xpath("description").text

    # Parse the description to extract structured data
    properties = {"name" => name}

    # Extract key-value pairs from CDATA description
    if description.include?("<br>")
      description.scan(/([^<:]+):\s*([^<]+)(?:<br>|$)/) do |key, value|
        clean_key = key.strip.downcase
        clean_value = value.strip

        # Handle coordinates specially
        if clean_key == "coordenadas"
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

    # Create a pseudo-GeoJSON feature (without geometry for non-geo features)
    {
      "type" => "Feature",
      "properties" => properties,
      "geometry" => nil
    }
  rescue => e
    log "Error extracting feature from placemark: #{e.message}"
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
        "slug", "name", "proposta", "sumario", "descricao", "eixo", "coordinates"
      )
      feature
    end
  end

  def download_images
    log "Processing images from gx_media_links..."

    image_count = 0

    @valid_features.each_with_index do |feature, index|
      properties = feature["properties"]
      next unless properties && properties["gx_media_links"]

      media_links = properties["gx_media_links"].to_s.strip
      next if media_links.empty?

      # Handle multiple URLs separated by whitespace or commas
      urls = media_links.split(/[\s,]+/).reject(&:empty?)
      downloaded_urls = []
      urls.each do |url|
        local_path = download_single_image(url)
        if local_path
          downloaded_urls << local_path
          image_count += 1
        end
      rescue => e
        log "Failed to download image #{url}: #{e.message}"
      end

      # Update the feature properties with local paths
      if downloaded_urls.any?
        properties["gx_media_links"] = downloaded_urls.join(" ")
      else
        # Remove the property if no images were downloaded
        properties.delete("gx_media_links")
      end
    end

    log "Downloaded #{image_count} images to #{@images_dir}/"
  end

  def generate_jekyll_pages
    log "Generating Jekyll pages for proposals with slugs..."

    generated_count = 0

    # Process geographical features
    @valid_features.each do |feature|
      generated_count += 1 if generate_page_for_feature(feature, true)
    end

    # Process non-geographical features
    @non_geo_features.each do |feature|
      generated_count += 1 if generate_page_for_feature(feature, false)
    end

    log "Generated #{generated_count} Jekyll pages total"
  end

  def generate_page_for_feature(feature, has_geometry)
    properties = feature["properties"]
    return false unless properties && properties["slug"] && !properties["slug"].to_s.strip.empty?

    slug = properties["slug"].to_s.strip
    page_path = "freguesias/#{freguesia_slug}/propostas/#{slug}.md"

    # Create directory if it doesn't exist
    FileUtils.mkdir_p(File.dirname(page_path))

    # Generate front matter
    front_matter = generate_front_matter(feature, has_geometry)

    # Write the page
    File.write(page_path, front_matter)
    log "Generated page: #{page_path} (#{has_geometry ? "with" : "without"} map location)"
    true
  end

  def generate_front_matter(feature, has_geometry = true)
    properties = feature["properties"]
    geometry = feature["geometry"]

    # Build front matter hash
    front_matter_hash = {
      "layout" => "proposta",
      "freguesia" => freguesia,
      "freguesia_slug" => freguesia_slug,
      "slug" => properties["slug"],
      "has_map_location" => has_geometry,
      "parties" => page_data["parties"],
      "under_construction" => page_data["under_construction"]
    }

    # Add all properties as front matter variables
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

    # Add geometry information
    if has_geometry && geometry
      front_matter_hash["geometry"] = {
        "type" => geometry["type"]
      }
      if geometry["coordinates"]
        front_matter_hash["geometry"]["coordinates"] = geometry["coordinates"]
      end
    elsif !has_geometry && properties["coordinates"]
      # For non-geo features, add coordinates as reference only
      front_matter_hash["reference_coordinates"] = properties["coordinates"]
    end

    # Convert to YAML and build final front matter
    front_matter = front_matter_hash.to_yaml
    front_matter += "---\n\n"
    front_matter += "<!-- This page was automatically generated from Google My Maps data -->\n"
    front_matter += "<!-- To edit this proposal, update the Google My Maps data and re-run the download script -->\n"
    if !has_geometry
      front_matter += "<!-- This proposal does not have a specific map location -->\n"
    end

    front_matter
  end

  def generate_propostas_index
    log "Generating #{freguesia_slug} propostas index page..."

    # Generate the index page content
    front_matter = {
      "layout" => "propostas",
      "freguesia_slug" => freguesia_slug,
      "freguesia" => page_data["freguesia"],
      "parties" => page_data["parties"],
      "title" => "Todas as Propostas",
      "description" => "Explore todas as propostas da coligação Viver #{freguesia} para as Eleições Autárquicas 2025",
      "under_construction" => page_data["under_construction"]
    }
    index_content = <<~FRONTMATTER
      #{front_matter.to_yaml}
      ---

    FRONTMATTER

    # Write the index page
    File.write("freguesias/#{freguesia_slug}/propostas/index.md", index_content)
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
      "name" => "#{@freguesia_slug.capitalize} Layer (#{my_google_maps_id})",
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

  def cleanup
    # Keep raw_data.kml for debugging multi-layer issues
    ["tmp/temp_data.geojson"].each do |file|
      File.delete(file) if File.exist?(file)
    end
    log "Cleaned up temporary files (keeping raw_data.kml for debugging)"
  end

  def print_summary
    file_size = File.size(@output_file)
    puts "✅ Successfully processed Google My Maps data!"
    puts "   📍 Map ID: #{my_google_maps_id}"
    puts "   📊 Valid features: #{@valid_features.length}"
    puts "   🖼️  Downloaded images: #{@downloaded_images.length}"

    # Count generated pages
    geo_features_with_slugs = @valid_features.count { |f| f["properties"] && f["properties"]["slug"] && !f["properties"]["slug"].to_s.strip.empty? }
    non_geo_features_with_slugs = @non_geo_features.count { |f| f["properties"] && f["properties"]["slug"] && !f["properties"]["slug"].to_s.strip.empty? }
    total_generated_pages = geo_features_with_slugs + non_geo_features_with_slugs
    puts "   📄 Generated pages: #{total_generated_pages} (#{geo_features_with_slugs} with location, #{non_geo_features_with_slugs} without location)"

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

  def freguesia
    freguesia_slug.humanize
  end
end
