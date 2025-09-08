module Jekyll
  module FreguesiaPrlUrlHelper
    # Generate relative URL for freguesia (for use in templates)
    def freguesia_relative_url(freguesia_slug, path = "")
      if Jekyll.env == "production"
        # Production: must use absolute URLs since it's cross-domain
        base_domain = "viver-lisboa.org"
        subdomain_url = "https://#{freguesia_slug}.#{base_domain}"

        if path.empty?
          subdomain_url
        else
          path = path.start_with?("/") ? path : "/#{path}"
          "#{subdomain_url}#{path}"
        end
      else
        # Development: can use relative URLs
        site = @context.registers[:site]
        baseurl = site.config["baseurl"] || ""

        if path.empty?
          "#{baseurl}/freguesias/#{freguesia_slug}/"
        else
          path = path.start_with?("/") ? path : "/#{path}"
          "#{baseurl}/freguesias/#{freguesia_slug}#{path}"
        end
      end
    end

    # Generate URL for main site (useful when linking back from freguesia pages)
    def main_site_url(path = "")
      if Jekyll.env == "production"
        # Production: link back to main domain
        main_url = "https://viver-lisboa.org"
        if path.empty?
          main_url
        else
          path = path.start_with?("/") ? path : "/#{path}"
          "#{main_url}#{path}"
        end
      else
        # Development: regular relative URLs
        site = @context.registers[:site]
        base_url = site.config["url"] || "http://localhost:4000"
        baseurl = site.config["baseurl"] || ""

        if path.empty?
          "#{base_url}#{baseurl}/"
        else
          path = path.start_with?("/") ? path : "/#{path}"
          "#{base_url}#{baseurl}#{path}"
        end
      end
    end
  end
end

# Register the filter
Liquid::Template.register_filter(Jekyll::FreguesiaPrlUrlHelper)
