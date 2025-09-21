module Jekyll
  module PageFilters
    # Check if a string starts with another string
    def starts_with(text, prefix)
      return false if text.nil? || prefix.nil?
      text.to_s.start_with?(prefix.to_s)
    end

    # Get all pages in the same directory as the current page
    def pages_in_same_directory(pages, current_page)
      return [] if current_page.nil? || current_page["path"].nil?

      # Get the directory of the current page
      current_dir = File.dirname(current_page["path"])
      current_dir = "propostas" if current_dir == "."

      # Filter pages in the same directory, excluding current page and index files
      pages.select do |page|
        page_dir = File.dirname(page["path"])
        page_name = File.basename(page["path"])

        page_dir == current_dir &&
          page["path"] != current_page["path"] &&
          page_name != "index.md" &&
          page_name != "index.html"
      end
    end

    # Get pages that start with a specific directory path
    def pages_starting_with(pages, directory_path)
      return [] if pages.nil? || directory_path.nil?

      dir_with_slash = directory_path.to_s.end_with?("/") ? directory_path.to_s : "#{directory_path}/"

      pages.select do |page|
        page["path"].to_s.start_with?(dir_with_slash)
      end
    end
  end
end

Liquid::Template.register_filter(Jekyll::PageFilters)
