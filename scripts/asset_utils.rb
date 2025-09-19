#!/usr/bin/env ruby

require "fileutils"
require "digest"
require "optparse"

class AssetUtils
  def initialize
    @root_dir = File.expand_path("..", __dir__)
    @site_dir = File.join(@root_dir, "_site")
    @assets_dir = File.join(@root_dir, "assets")
  end

  def clean_fingerprinted_assets
    puts "Cleaning fingerprinted assets..."

    # Remove fingerprinted assets from source
    Dir.glob(File.join(@assets_dir, "**", "*-????????.*")).each do |file|
      File.delete(file)
      puts "Removed: #{File.basename(file)}"
    end

    # Remove fingerprinted assets from built site
    if Dir.exist?(@site_dir)
      Dir.glob(File.join(@site_dir, "assets", "**", "*-????????.*")).each do |file|
        File.delete(file)
        puts "Removed: #{File.basename(file)}"
      end
    end

    puts "Cleanup complete!"
  end

  def list_fingerprinted_assets
    puts "Fingerprinted assets in built site:"
    puts "=" * 50

    return unless Dir.exist?(@site_dir)

    fingerprinted_files = Dir.glob(File.join(@site_dir, "assets", "**", "*-????????.*"))

    if fingerprinted_files.empty?
      puts "No fingerprinted assets found. Run 'bundle exec jekyll build' first."
      return
    end

    fingerprinted_files.sort.each do |file|
      relative_path = file.sub(@site_dir, "")
      file_size = File.size(file)
      puts "#{relative_path} (#{format_bytes(file_size)})"
    end

    puts "\nTotal: #{fingerprinted_files.size} files"
  end

  def verify_cache_headers
    headers_file = File.join(@root_dir, "_headers")

    unless File.exist?(headers_file)
      puts "ERROR: _headers file not found!"
      return
    end

    puts "Verifying cache headers configuration..."
    puts "=" * 50

    content = File.read(headers_file)

    # Check for fingerprinted asset rules
    checks = [
      {
        pattern: "/assets/css/*-????????.css",
        description: "CSS fingerprinted assets"
      },
      {
        pattern: "/assets/js/*-????????.js",
        description: "JS fingerprinted assets"
      },
      {
        pattern: "/assets/images/*-????????.*",
        description: "Image fingerprinted assets"
      },
      {
        pattern: "Cache-Control: public, max-age=31536000, immutable",
        description: "Long-term caching for fingerprinted assets"
      }
    ]

    checks.each do |check|
      if content.include?(check[:pattern])
        puts "✓ #{check[:description]}: OK"
      else
        puts "✗ #{check[:description]}: MISSING"
      end
    end

    puts "\n_headers file content:"
    puts "-" * 30
    puts content
  end

  def generate_cache_manifest
    return unless Dir.exist?(@site_dir)

    manifest = {
      generated_at: Time.now.utc.iso8601,
      fingerprinted_assets: {},
      cache_strategy: {
        fingerprinted: "max-age=31536000, immutable",
        non_fingerprinted: "max-age=3600"
      }
    }

    # Find all fingerprinted assets
    Dir.glob(File.join(@site_dir, "assets", "**", "*-????????.*")).each do |file|
      relative_path = file.sub(@site_dir, "")
      original_name = File.basename(file).sub(/-[a-f0-9]{8}(\.\w+)$/, '\1')
      original_path = File.join(File.dirname(relative_path), original_name)

      manifest[:fingerprinted_assets][original_path] = relative_path
    end

    manifest_file = File.join(@site_dir, "assets", "manifest.json")
    FileUtils.mkdir_p(File.dirname(manifest_file))
    File.write(manifest_file, JSON.pretty_generate(manifest))

    puts "Generated cache manifest: #{manifest_file}"
    puts "Fingerprinted assets: #{manifest[:fingerprinted_assets].size}"
  end

  def show_asset_stats
    return unless Dir.exist?(@site_dir)

    puts "Asset Statistics"
    puts "=" * 50

    asset_types = {}
    total_size = 0
    fingerprinted_count = 0

    Dir.glob(File.join(@site_dir, "assets", "**", "*")).each do |file|
      next unless File.file?(file)

      ext = File.extname(file).downcase
      size = File.size(file)

      asset_types[ext] ||= {count: 0, size: 0, fingerprinted: 0}
      asset_types[ext][:count] += 1
      asset_types[ext][:size] += size

      if /-[a-f0-9]{8}\./.match?(File.basename(file))
        asset_types[ext][:fingerprinted] += 1
        fingerprinted_count += 1
      end

      total_size += size
    end

    asset_types.sort.each do |ext, stats|
      fingerprint_pct = (stats[:count] > 0) ? (stats[:fingerprinted].to_f / stats[:count] * 100).round(1) : 0
      puts sprintf("%-10s: %3d files, %8s, %4.1f%% fingerprinted",
        ext.empty? ? "(no ext)" : ext,
        stats[:count],
        format_bytes(stats[:size]),
        fingerprint_pct)
    end

    puts "-" * 50
    puts sprintf("%-10s: %3d files, %8s, %4.1f%% fingerprinted",
      "TOTAL",
      asset_types.values.sum { |s| s[:count] },
      format_bytes(total_size),
      (asset_types.values.sum { |s| s[:count] } > 0) ?
        (fingerprinted_count.to_f / asset_types.values.sum { |s| s[:count] } * 100).round(1) : 0)
  end

  private

  def format_bytes(bytes)
    units = %w[B KB MB GB]
    size = bytes.to_f
    unit = 0

    while size >= 1024 && unit < units.length - 1
      size /= 1024
      unit += 1
    end

    sprintf("%.1f%s", size, units[unit])
  end
end

# CLI interface
if __FILE__ == $0
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options] COMMAND"
    opts.separator ""
    opts.separator "Commands:"
    opts.separator "    clean     Clean all fingerprinted assets"
    opts.separator "    list      List fingerprinted assets"
    opts.separator "    verify    Verify cache headers configuration"
    opts.separator "    manifest  Generate cache manifest file"
    opts.separator "    stats     Show asset statistics"
    opts.separator ""
  end.parse!

  command = ARGV[0]
  utils = AssetUtils.new

  case command
  when "clean"
    utils.clean_fingerprinted_assets
  when "list"
    utils.list_fingerprinted_assets
  when "verify"
    utils.verify_cache_headers
  when "manifest"
    utils.generate_cache_manifest
  when "stats"
    utils.show_asset_stats
  else
    puts "Available commands: clean, list, verify, manifest, stats"
    puts "Run with --help for more information"
  end
end
