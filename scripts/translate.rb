require "deepl"
require_relative "google_sheets_cache"

class Translate
  attr_reader :cache, :language

  # DeepL API limits
  MAX_TEXT_LENGTH = 4000  # Conservative limit to avoid issues
  CHUNK_SEPARATOR = "\n\n"  # Prefer to split on paragraph breaks

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

  def translate(text, chunking_depth = 0)
    return text if text.nil? || text.strip.empty?

    # Prevent infinite recursion
    if chunking_depth > 3
      puts "Warning: Maximum chunking depth exceeded. Returning original text."
      return text
    end

    # Log what we're about to translate
    puts "\n" + "=" * 60
    puts "TRANSLATION REQUEST (#{@language.upcase})"
    puts "Length: #{text.length} characters"
    puts "Preview: #{text[0..100]}#{"..." if text.length > 100}"
    puts "=" * 60

    # Check cache first
    cached_result = @cache.get(text, @language)
    if cached_result
      puts "✓ Found in cache, skipping API call"
      return cached_result
    end

    # If text is too long, chunk it
    if text.length > MAX_TEXT_LENGTH
      puts "⚠ Text too long (#{text.length} chars), will chunk into smaller pieces"
      return translate_chunked_text(text, chunking_depth)
    end

    translate_single_text(text, chunking_depth)
  end

  private

  def translate_single_text(text, chunking_depth = 0)
    # Check if text is too long for our conservative limit
    if text.length > MAX_TEXT_LENGTH
      puts "❌ Text too long for single API call (#{text.length} chars). Chunking..."
      return translate_chunked_text(text, chunking_depth + 1)
    end

    puts "🚀 Making DeepL API call..."
    puts "   Text: \"#{text[0..200]}#{"..." if text.length > 200}\""
    puts "   Length: #{text.length} characters"
    puts "   Target language: #{@language.upcase}"

    # Add small delay to be respectful to the API
    sleep(0.5)

    retries = 0
    max_retries = 3

    begin
      translation = DeepL.translate(
        text,
        "PT", # Source language (Portuguese)
        @language.upcase # Target language
      )
    rescue DeepL::Exceptions::LimitExceeded
      retries += 1
      if retries <= max_retries
        wait_time = retries * 5
        puts "⏰ DeepL rate limit exceeded. Waiting #{wait_time} seconds before retry #{retries}/#{max_retries}..."
        sleep(wait_time)
        retry
      else
        puts "❌ DeepL rate limit exceeded after #{max_retries} retries. Returning original text."
        return text
      end
    end

    translated_text = translation.text

    puts "✅ Translation successful!"
    puts "   Original: \"#{text[0..100]}#{"..." if text.length > 100}\""
    puts "   Translated: \"#{translated_text[0..100]}#{"..." if translated_text.length > 100}\""

    # Store in cache
    @cache.set(text, @language, translated_text)

    translated_text
  rescue DeepL::Exceptions::AuthorizationFailed
    puts "❌ DeepL authentication failed. Check your API key."
    text
  rescue DeepL::Exceptions::QuotaExceeded
    puts "❌ DeepL quota exceeded. Check your usage limits."
    text
  rescue => e
    puts "❌ Translation error: #{e.message}"
    puts "   Error class: #{e.class}"
    text # Return original text if translation fails
  end

  def translate_chunked_text(text, chunking_depth = 0)
    puts "\n📝 CHUNKING TEXT FOR TRANSLATION"
    puts "   Original length: #{text.length} characters"
    puts "   Chunking depth: #{chunking_depth}"

    # Try to split on paragraph breaks first
    chunks = smart_chunk_text(text)

    # Verify all chunks are within limit
    oversized_chunks = chunks.select { |chunk| chunk.length > MAX_TEXT_LENGTH }
    if oversized_chunks.any?
      puts "⚠ Warning: #{oversized_chunks.length} chunks are still too large. Forcing smaller chunks..."
      chunks = force_small_chunks(text)
    end

    puts "📋 Created #{chunks.length} chunks:"
    chunks.each_with_index do |chunk, index|
      puts "   Chunk #{index + 1}: #{chunk.length} chars - \"#{chunk[0..50]}#{"..." if chunk.length > 50}\""
    end

    puts "\n🔄 About to translate #{chunks.length} chunks. This will make #{chunks.length} API calls."

    translated_chunks = chunks.map.with_index do |chunk, index|
      puts "\n📦 Processing chunk #{index + 1}/#{chunks.length} (#{chunk.length} chars)"

      # Check cache for each chunk
      cached_chunk = @cache.get(chunk, @language)
      if cached_chunk
        puts "✓ Chunk #{index + 1} found in cache"
        cached_chunk
      else
        puts "🔄 Chunk #{index + 1} needs translation"
        translate_single_text(chunk, chunking_depth)
      end
    end

    result = translated_chunks.join("")

    puts "\n✅ All chunks translated successfully!"
    puts "   Combined result length: #{result.length} characters"

    # Cache the full result as well
    @cache.set(text, @language, result)

    result
  end

  def smart_chunk_text(text)
    # If text is small enough, return as is
    return [text] if text.length <= MAX_TEXT_LENGTH

    chunks = []
    remaining_text = text

    while remaining_text.length > MAX_TEXT_LENGTH
      # Try to find a good break point
      chunk_size = MAX_TEXT_LENGTH
      break_point = find_break_point(remaining_text, chunk_size)

      chunk = remaining_text[0...break_point]
      chunks << chunk
      remaining_text = remaining_text[break_point..-1]
    end

    # Add remaining text as final chunk
    chunks << remaining_text if remaining_text.length > 0

    chunks
  end

  def find_break_point(text, max_length)
    # If text is shorter than max, return full length
    return text.length if text.length <= max_length

    # Look for paragraph breaks first
    last_paragraph_break = text.rindex(CHUNK_SEPARATOR, max_length)
    return last_paragraph_break + CHUNK_SEPARATOR.length if last_paragraph_break

    # Look for sentence breaks
    last_sentence_break = text.rindex(". ", max_length)
    return last_sentence_break + 2 if last_sentence_break

    # Look for any whitespace
    last_space = text.rindex(" ", max_length)
    return last_space + 1 if last_space

    # If no good break point, just cut at max length
    max_length
  end

  def force_small_chunks(text)
    chunks = []
    remaining_text = text

    while remaining_text.length > 0
      chunk_size = [MAX_TEXT_LENGTH, remaining_text.length].min
      chunks << remaining_text[0...chunk_size]
      remaining_text = remaining_text[chunk_size..-1]
    end

    chunks
  end

  public

  def flush_cache
    @cache.flush
  end
end
