class PreparePmtiles
  def initialize(freguesia_slug:)
    @freguesia_slug = freguesia_slug
    @output = "assets/data/#{freguesia_slug}.pmtiles"
    @sources = [
      "tmp/#{freguesia_slug}/propostas.geojson",
      "data/freguesias/#{freguesia_slug}/border.geojson"
    ]
  end

  def prepare
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
      "--force",
      "-o", @output
    ] + @sources

    p cmd

    stdout, stderr, status = Open3.capture3(*cmd)
    $stdout.print stdout
    $stderr.print stderr

    puts "✅ Successfully generated PMTiles: #{@output}"
    puts "   Layers included: #{@sources.map { |f| File.basename(f, ".geojson") }.join(", ")}"
    puts "   File size: #{File.size("#{@output}")} bytes"
  end
end
