require 'digest'
require 'fileutils'

module Jekyll
  # Liquid filters for asset URLs
  module AssetHashFilters
    def asset_url(input)
      site = @context.registers[:site]
      asset_hashes = site.data['asset_hashes'] || {}

      # Normalize the input to ensure it starts with /
      normalized_input = input.start_with?('/') ? input : "/#{input}"

      # Return hashed URL if available, otherwise return original
      hashed_url = asset_hashes[normalized_input]
      hashed_url || normalized_input
    end

    def asset_path(input)
      # Alias for asset_url for compatibility
      asset_url(input)
    end
  end

  # Hook to fingerprint assets after site is written
  Jekyll::Hooks.register :site, :post_write do |site|
    config = site.config['asset_fingerprinting'] || {}

    # Skip if explicitly disabled
    next if config.key?('enabled') && !config['enabled']

    algorithm = config['algorithm'] || 'md5'
    length = config['length'] || 8
    asset_hashes = {}

    # Asset extensions to fingerprint
    asset_extensions = %w[.css .js .png .jpg .jpeg .gif .svg .ico .woff .woff2 .ttf .eot .pmtiles]

    Jekyll.logger.info "Asset Hash:", "Starting post-build asset fingerprinting..."

    # Find all asset files in the built site
    Dir.glob(File.join(site.dest, 'assets', '**', '*')).each do |file_path|
      next unless File.file?(file_path)

      ext = File.extname(file_path).downcase
      next unless asset_extensions.include?(ext)

      # Skip if already fingerprinted (contains hash pattern)
      next if File.basename(file_path) =~ /-[a-f0-9]{8}\./

      # Generate hash of file content
      content = File.read(file_path, mode: 'rb')
      hash = case algorithm
             when 'sha1'
               Digest::SHA1.hexdigest(content)[0, length]
             when 'sha256'
               Digest::SHA256.hexdigest(content)[0, length]
             else
               Digest::MD5.hexdigest(content)[0, length]
             end

      # Create fingerprinted filename
      basename = File.basename(file_path, ext)
      dirname = File.dirname(file_path)
      hashed_filename = "#{basename}-#{hash}#{ext}"
      hashed_path = File.join(dirname, hashed_filename)

      # Copy file with fingerprinted name
      FileUtils.cp(file_path, hashed_path)

      # Store mapping for future builds (URLs relative to site root)
      original_url = file_path.sub(site.dest, '')
      hashed_url = hashed_path.sub(site.dest, '')

      asset_hashes[original_url] = hashed_url

      Jekyll.logger.debug "Asset Hash:", "Created #{hashed_filename}"
    end

    # Save asset hash mapping for this build
    site.data['asset_hashes'] = asset_hashes

    Jekyll.logger.info "Asset Hash:", "Fingerprinted #{asset_hashes.size} assets"

    # Update HTML files to use fingerprinted assets
    update_html_files(site, asset_hashes)
  end

  # Update HTML files to reference fingerprinted assets
  def self.update_html_files(site, asset_hashes)
    return if asset_hashes.empty?

    Jekyll.logger.info "Asset Hash:", "Updating HTML files with fingerprinted asset URLs..."

    Dir.glob(File.join(site.dest, '**', '*.html')).each do |html_file|
      content = File.read(html_file)
      modified = false

      asset_hashes.each do |original_url, hashed_url|
        # Update various asset reference patterns
        patterns = [
          /href=["']#{Regexp.escape(original_url)}["']/,
          /src=["']#{Regexp.escape(original_url)}["']/,
          /url\(["']?#{Regexp.escape(original_url)}["']?\)/,
          /"#{Regexp.escape(original_url)}"/
        ]

        patterns.each do |pattern|
          if content.match?(pattern)
            content.gsub!(pattern) do |match|
              match.gsub(original_url, hashed_url)
            end
            modified = true
          end
        end
      end

      if modified
        File.write(html_file, content)
        Jekyll.logger.debug "Asset Hash:", "Updated #{File.basename(html_file)}"
      end
    end
  end
end

# Register the filter
Liquid::Template.register_filter(Jekyll::AssetHashFilters)
