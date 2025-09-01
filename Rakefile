require "json"
require "http"
require "rake/clean"
require "open3"
require "jekyll"

# Load the downloader class
require_relative "scripts/download_maps"
require_relative "scripts/prepare_pmtiles"

directory "tmp"

desc "Prepare freguesia data"
task freguesias: ["tmp"] do
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

  freguesia_pages.each do |page|
    puts "\nProcessing: #{page.path}"

    # Extract freguesia slug from path
    freguesia_slug = page.path.split('/')[1]

    downloader = GoogleMyMapsDownloader.new(
      freguesia_slug: freguesia_slug,
      maps_id: page.data["my_google_map_id"],
      verbose: true
    )
    downloader.download_and_process

    pmtiles_preparer = PreparePmtiles.new(freguesia_slug: freguesia_slug)
    pmtiles_preparer.prepare
  end
end

desc "Download data and generate PMTiles (full workflow)"
task build: :freguesias

# Files to clean
CLEAN.include("tmp/*")
CLEAN.include("assets/data/*.pmtiles")
CLEAN.include("assets/data/images/*")
CLEAN.include("freguesias/*/propostas/*")
