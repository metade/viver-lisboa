require "google/apis/sheets_v4"
require "googleauth"
require "json"
require "stringio"

class GoogleSheetsCache
  SCOPES = [Google::Apis::SheetsV4::AUTH_SPREADSHEETS].freeze

  def initialize(spreadsheet_id, credentials_path: nil)
    @spreadsheet_id = spreadsheet_id
    @service = Google::Apis::SheetsV4::SheetsService.new
    @service.client_options.application_name = "Viver Lisboa Translation Cache"
    @service.authorization = authorize(credentials_path)
    @local_cache = {}
    @dirty_sheets = Set.new
  end

  def get(text, target_language)
    load_sheet_cache(target_language) unless @local_cache[target_language]
    @local_cache.dig(target_language, text)
  end

  def set(text, target_language, translation)
    @local_cache[target_language] ||= {}
    @local_cache[target_language][text] = translation
    @dirty_sheets << target_language
  end

  def flush
    puts "Flushing cache for languages: #{@dirty_sheets.to_a}"
    @dirty_sheets.each do |language|
      cache_size = @local_cache[language] ? @local_cache[language].size : 0
      puts "Language #{language}: #{cache_size} translations to flush"
      update_sheet(language)
    end
    @dirty_sheets.clear
  end

  private

  def authorize(credentials_path)
    # Try environment variable first (for CI/CD)
    if ENV["GOOGLE_CREDENTIALS_JSON"]
      puts "Using Google credentials from GOOGLE_CREDENTIALS_JSON environment variable"
      credentials_json = JSON.parse(ENV["GOOGLE_CREDENTIALS_JSON"])
      Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: StringIO.new(credentials_json.to_json),
        scope: SCOPES
      )
    elsif credentials_path && File.exist?(credentials_path)
      puts "Using Google credentials from file: #{credentials_path}"
      Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: File.open(credentials_path),
        scope: SCOPES
      )
    elsif File.exist?(ENV["GOOGLE_APPLICATION_CREDENTIALS"] || "credentials.json")
      credentials_file = ENV["GOOGLE_APPLICATION_CREDENTIALS"] || "credentials.json"
      puts "Using Google credentials from file: #{credentials_file}"
      Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: File.open(credentials_file),
        scope: SCOPES
      )
    else
      puts "Attempting to use default application credentials"
      # Fallback to default application credentials
      Google::Auth.get_application_default(SCOPES)
    end
  rescue JSON::ParserError => e
    raise "Failed to parse Google credentials JSON: #{e.message}. " \
          "Make sure GOOGLE_CREDENTIALS_JSON contains valid JSON."
  rescue => e
    raise "Failed to authorize Google Sheets access: #{e.message}. " \
          "Options: 1) Set GOOGLE_CREDENTIALS_JSON env var with service account JSON, " \
          "2) Set GOOGLE_APPLICATION_CREDENTIALS to credentials file path, " \
          "3) Place credentials.json in project root, " \
          "4) Use Application Default Credentials."
  end

  def load_sheet_cache(language)
    sheet_name = sheet_name_for_language(language)

    begin
      # Try to get existing sheet data
      response = @service.get_spreadsheet_values(
        @spreadsheet_id,
        "#{sheet_name}!A:C",
        value_render_option: "UNFORMATTED_VALUE"
      )

      @local_cache[language] = {}

      if response.values
        response.values.each_with_index do |row, index|
          next if index == 0 # Skip header row
          next unless row.length >= 3

          original_text, translation, _timestamp = row
          next if original_text.nil? || original_text.strip.empty?

          @local_cache[language][original_text] = translation
        end
      end
    rescue Google::Apis::ClientError => e
      # Check both the error body and message for range parsing issues
      error_indicates_missing_sheet = e.status_code == 400 && (
          (e.body && e.body.include?("Unable to parse range")) ||
          e.message.include?("Unable to parse range") ||
          e.message.include?("not found") ||
          (e.body && e.body.include?("not found"))
        )

      if error_indicates_missing_sheet
        # Sheet doesn't exist, create it
        create_sheet(language)
        @local_cache[language] = {}
      else
        puts "Google Sheets API error: #{e.message}"
        puts "Error body: #{e.body}" if e.body
        raise e
      end
    end
  end

  def update_sheet(language)
    puts "Updating sheet for language: #{language}"
    puts "Local cache for #{language}: #{@local_cache[language] ? @local_cache[language].keys : "nil"}"

    return unless @local_cache[language] && !@local_cache[language].empty?

    sheet_name = sheet_name_for_language(language)
    ensure_sheet_exists(language)

    # Prepare data with headers
    rows = [["Original Text", "Translation", "Last Updated"]]

    @local_cache[language].each do |original_text, translation|
      rows << [original_text, translation, Time.now.strftime("%Y-%m-%d %H:%M:%S")]
    end

    # Clear existing content and update with new data
    clear_request = Google::Apis::SheetsV4::ClearValuesRequest.new
    @service.clear_values(@spreadsheet_id, "#{sheet_name}!A:C", clear_request)

    # Update with new data
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: rows)
    @service.update_spreadsheet_value(
      @spreadsheet_id,
      "#{sheet_name}!A1",
      value_range,
      value_input_option: "USER_ENTERED"
    )

    puts "Updated Google Sheet '#{sheet_name}' with #{rows.length - 1} translations"
  rescue => e
    puts "Error updating sheet '#{sheet_name}': #{e.message}"
    raise e
  end

  def ensure_sheet_exists(language)
    sheet_name = sheet_name_for_language(language)

    begin
      @service.get_spreadsheet(@spreadsheet_id)

      # Check if sheet exists
      spreadsheet = @service.get_spreadsheet(@spreadsheet_id)
      sheet_exists = spreadsheet.sheets.any? { |sheet| sheet.properties.title == sheet_name }

      create_sheet(language) unless sheet_exists
    rescue Google::Apis::ClientError => e
      raise "Failed to access spreadsheet: #{e.message}. " \
            "Make sure the spreadsheet ID is correct and the service account has access."
    end
  end

  def create_sheet(language)
    sheet_name = sheet_name_for_language(language)

    requests = [
      {
        add_sheet: {
          properties: {
            title: sheet_name,
            grid_properties: {
              row_count: 1000,
              column_count: 3,
              frozen_row_count: 1
            }
          }
        }
      }
    ]

    batch_update_request = Google::Apis::SheetsV4::BatchUpdateSpreadsheetRequest.new(
      requests: requests
    )

    @service.batch_update_spreadsheet(@spreadsheet_id, batch_update_request)

    # Add headers
    headers = [["Original Text", "Translation", "Last Updated"]]
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: headers)
    @service.update_spreadsheet_value(
      @spreadsheet_id,
      "#{sheet_name}!A1",
      value_range,
      value_input_option: "USER_ENTERED"
    )

    # Format headers (bold)
    format_requests = [
      {
        repeat_cell: {
          range: {
            sheet_id: get_sheet_id(sheet_name),
            start_row_index: 0,
            end_row_index: 1
          },
          cell: {
            user_entered_format: {
              text_format: {
                bold: true
              }
            }
          },
          fields: "userEnteredFormat.textFormat.bold"
        }
      }
    ]

    format_batch_request = Google::Apis::SheetsV4::BatchUpdateSpreadsheetRequest.new(
      requests: format_requests
    )

    @service.batch_update_spreadsheet(@spreadsheet_id, format_batch_request)

    puts "Created new sheet '#{sheet_name}' for #{language} translations"
  end

  def get_sheet_id(sheet_name)
    spreadsheet = @service.get_spreadsheet(@spreadsheet_id)
    sheet = spreadsheet.sheets.find { |s| s.properties.title == sheet_name }
    sheet&.properties&.sheet_id
  end

  def sheet_name_for_language(language)
    "translations_#{language.downcase}"
  end
end
