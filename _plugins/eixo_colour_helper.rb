module Jekyll
  module EixoColourHelper
    def eixo_badge_class(eixo, freguesia_slug)
      colour = freguesia_eixo_colour_mapping(freguesia_slug)[eixo]
      if colour
        "badge-eixo-#{colour["className"]}"
      else
        "badge-eixo-overflow"
      end
    end

    def freguesia_eixo_colour_mapping(freguesia_slug)
      page = @context.registers[:page]
      return page["eixos_colour_map"] if page["eixos_colour_map"]

      site = @context.registers[:site]
      propostas_page = site.pages.find { |page|
        page.path == "freguesias/#{freguesia_slug}/propostas/index.md"
      }
      return {} if propostas_page.nil?

      propostas_page["eixos_colour_map"] || {}
    end

    def my_to_json(input)
      JSON.generate(input)
    end

    private

    def eixo_colours
      @context.registers[:site].data.dig("eixo_colors", "colors")
    end
  end
end

# Register the filter
Liquid::Template.register_filter(Jekyll::EixoColourHelper)
