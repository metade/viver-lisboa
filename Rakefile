require "json"
require "http"
require "rake/clean"
require "open3"
require "jekyll"

# Load the downloader class
require_relative "scripts/download_maps"
require_relative "scripts/prepare_pmtiles"

directory "tmp"

# Helper method to process freguesia data
def process_freguesia(freguesia_slug, page_data)
  puts "\nProcessing: #{freguesia_slug}"

  downloader = GoogleMyMapsDownloader.new(
    freguesia_slug: freguesia_slug,
    page_data: page_data,
    verbose: true
  )
  downloader.download_and_process

  pmtiles_preparer = PreparePmtiles.new(freguesia_slug: freguesia_slug)
  pmtiles_preparer.prepare
end

# Helper method to initialize Jekyll site and get freguesia pages
def get_freguesia_pages
  config = Jekyll.configuration({
    "source" => Dir.pwd,
    "destination" => "_site"
  })

  site = Jekyll::Site.new(config)
  site.read

  site.pages.select do |page|
    page.path.match?(/^freguesias\/[^\/]+\/index\.html$/)
  end
end

desc "Process data for a specific freguesia"
task :freguesia, [:freguesia_slug] => ["tmp"] do |t, args|
  unless args.freguesia_slug
    puts "Error: freguesia_slug argument is required"
    puts "Usage: rake freguesia[freguesia_slug]"
    puts "Example: rake freguesia[alvalade]"
    exit 1
  end

  # Find the specific freguesia page
  freguesia_pages = get_freguesia_pages
  freguesia_page = freguesia_pages.find do |page|
    page.path.split("/")[1] == args.freguesia_slug
  end

  if freguesia_page.nil?
    puts "Error: No freguesia found with slug '#{args.freguesia_slug}'"
    puts "Available freguesias:"
    freguesia_pages.each { |p| puts "  - #{p.path.split("/")[1]}" }
    exit 1
  end

  process_freguesia(args.freguesia_slug, freguesia_page.data)
end

desc "Process data for all freguesias"
task freguesias: ["tmp"] do
  freguesia_pages = get_freguesia_pages

  freguesia_pages.each do |page|
    # Extract freguesia slug from path
    freguesia_slug = page.path.split("/")[1]
    process_freguesia(freguesia_slug, page.data)
  end
end

desc "Download data and generate PMTiles (full workflow)"
task build: :freguesias

desc "Clean assets and build artifacts"
task :clean_assets do
  puts "Cleaning fingerprinted assets..."
  system("ruby scripts/asset_utils.rb clean") if File.exist?("scripts/asset_utils.rb")
end

desc "Show asset statistics"
task :asset_stats do
  system("ruby scripts/asset_utils.rb stats") if File.exist?("scripts/asset_utils.rb")
end

# Files to clean
CLEAN.include("tmp/*")
CLEAN.include("assets/data/*.pmtiles")
CLEAN.include("assets/data/images/*")
CLEAN.include("freguesias/*/propostas/*")
CLEAN.include("freguesias/*/programa.md")
CLEAN.include("_site/**/*")
CLOBBER.include("assets/**/*-[a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9].*")
