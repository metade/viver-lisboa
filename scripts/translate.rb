require "deepl"
require_relative "google_sheets_cache"

class Translate
  attr_reader :cache, :language

  def initialize(language, spreadsheet_id, credentials_path: nil, api_key: nil)
    @language = language
    @cache = GoogleSheetsCache.new(spreadsheet_id, credentials_path: credentials_path)

    api_key ||= ENV["DEEPL_API_KEY"]
    raise ArgumentError, "DeepL API key is required. Set DEEPL_API_KEY environment variable or pass api_key parameter." unless api_key

    DeepL.configure do |config|
      config.auth_key = api_key
      config.host = "https://api-free.deepl.com" # Use 'https://api.deepl.com' for paid plans
    end
  end

  def translate(text)
    return text if text.nil? || text.strip.empty?

    # Check cache first
    cached_result = @cache.get(text, @language)
    return cached_result if cached_result

    begin
      translation = DeepL.translate(
        text,
        "PT", # Source language (Portuguese)
        @language.upcase # Target language
      )

      translated_text = translation.text

      # Store in cache
      @cache.set(text, @language, translated_text)

      translated_text
    rescue DeepL::Exceptions::AuthorizationFailed
      puts "DeepL authentication failed. Check your API key."
      text
    rescue DeepL::Exceptions::QuotaExceeded
      puts "DeepL quota exceeded. Check your usage limits."
      text
    rescue DeepL::Exceptions::LimitExceeded
      puts "DeepL character limit exceeded for this request."
      text
    rescue => e
      puts "Translation error: #{e.message}"
      text # Return original text if translation fails
    end
  end

  def flush_cache
    @cache.flush
  end
end
