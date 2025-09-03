source "https://rubygems.org"

# Jekyll version
gem "jekyll", "~> 4.4.1"
gem "logger"
gem "http", "~> 5.0"
gem "activesupport"

# Jekyll plugins
group :jekyll_plugins do
  gem "jekyll-feed", "~> 0.12"
  gem "jekyll-sitemap"
  gem "jekyll-seo-tag"
end

# Development dependencies
group :development do
  gem "standardrb", "~> 1.0"
  gem "webrick", git: "https://github.com/metade/webrick.git", branch: "fix-if-range-header-returning-304"
end

# Windows and JRuby does not include zoneinfo files, so bundle the tzinfo-data gem
# and associated library.
platforms :windows do
  gem "tzinfo", ">= 1", "< 3"
  gem "tzinfo-data"
end

# Performance-booster for watching directories on Windows
gem "wdm", "~> 0.1.1", platforms: [:windows]

# Lock `http_parser.rb` gem to `v0.6.x` on JRuby builds since newer versions of the gem
# do not have a Java counterpart.
gem "http_parser.rb", "~> 0.6.0", platforms: [:jruby]
