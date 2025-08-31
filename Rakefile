require "json"
require "http"
require "rake/clean"
require "open3"
require "jekyll"

# Load the downloader class
require_relative "scripts/download_maps"

directory "tmp"

file "tmp/propostas.geojson" => "tmp" do
  # Get the Google My Maps ID from environment variable
  maps_id = ENV["MY_GOOGLE_MAPS_ID"]
  if maps_id.nil? || maps_id.empty?
    puts "Error: MY_GOOGLE_MAPS_ID environment variable is required"
    puts "Usage: MY_GOOGLE_MAPS_ID=your_map_id rake tmp/propostas.geojson"
    puts ""
    puts "To get your Google My Maps ID:"
    puts "1. Open your Google My Maps"
    puts "2. Click Share > View on web"
    puts "3. Copy the ID from the URL: https://www.google.com/maps/d/viewer?mid=YOUR_ID_HERE"
    exit 1
  end

  # Use the GoogleMyMapsDownloader class directly
  puts "Downloading Google My Maps data for 'propostas' layer..."
  downloader = GoogleMyMapsDownloader.new(
    maps_id: maps_id,
    layer_name: "propostas",
    verbose: true
  )

  begin
    downloader.download_and_process
    puts "✅ Successfully downloaded and processed Google My Maps data!"
  rescue => e
    puts "❌ Error: #{e.message}"
    puts "Check that:"
    puts "  - Your map ID is correct"
    puts "  - Your map is publicly accessible"
    puts "  - You have GDAL installed"
    exit 1
  end
end

file "assets/data/data.pmtiles" => ["tmp/propostas.geojson", "data/arroios.geojson"] do |task|
  # Check if tippecanoe is available
  unless system("which tippecanoe > /dev/null 2>&1")
    puts "Error: Tippecanoe is required but not found"
    puts "Install with: brew install tippecanoe (macOS) or build from source"
    exit 1
  end

  cmd = [
    "tippecanoe",
    "-Z", "0", "-z", "12",
    "--no-feature-limit",
    "--no-tile-size-limit",
    "--simplification=1",
    "-o", task.name
  ] + task.sources

  p cmd

  stdout, stderr, status = Open3.capture3(*cmd)
  $stdout.print stdout
  $stderr.print stderr

  puts "✅ Successfully generated PMTiles: #{task.name}"
  puts "   Layers included: #{task.sources.map { |f| File.basename(f, ".geojson") }.join(", ")}"
  puts "   File size: #{File.size("#{task.name}")} bytes"
end

desc "Prepare freguesia data"
task :freguesias do
  # Initialize Jekyll site
  config = Jekyll.configuration({
    'source' => Dir.pwd,
    'destination' => '_site'
  })

  site = Jekyll::Site.new(config)
  site.read

  # Filter for freguesia pages
  freguesia_pages = site.pages.select do |page|
    page.path.match?(/^freguesias\/[^\/]+\/index\.html$/)
  end

  if freguesia_pages.empty?
    puts "No freguesia pages found"
    exit 1
  end

  puts "Found #{freguesia_pages.length} freguesia pages:"

  freguesias_data = []

  freguesia_pages.each do |page|
    puts "\nProcessing: #{page.path}"

    # Extract freguesia slug from path
    freguesia_slug = page.path.split('/')[1]

    # Get all front matter data
    front_matter = page.data.dup
    front_matter['freguesia_slug'] = freguesia_slug
    front_matter['url'] = page.url

    freguesias_data << front_matter

    puts "  ✅ Parsed front matter:"
    front_matter.each do |key, value|
      puts "    #{key}: #{value.is_a?(Array) ? value.join(', ') : value}"
    end
  end

  puts "\n" + "="*50
  puts "SUMMARY: Processed #{freguesias_data.length} freguesias"
  puts "="*50

  # Save to JSON file for further processing
  output_file = "tmp/freguesias_data.json"
  FileUtils.mkdir_p("tmp")
  File.write(output_file, JSON.pretty_generate(freguesias_data))
  puts "Data saved to: #{output_file}"
end

desc "Download data and generate PMTiles (full workflow)"
task build: "assets/data/data.pmtiles"

# Files to clean
CLEAN.include("tmp/*.geojson")
CLEAN.include("tmp/raw_data.kml")
CLEAN.include("tmp/temp_data.geojson")
CLEAN.include("assets/data/data.pmtiles")
CLEAN.include("assets/data/images/*")
CLEAN.include("propostas/*")
