require "rqrcode"
require "prawn"
require "chunky_png"

class QRCodeGenerator
  attr_reader :data, :output_path

  def self.call(data, output_path)
    new(data, output_path).call
  end

  def initialize(data, output_path)
    @data = data
    @output_path = output_path
  end

  def call
    Prawn::Document.generate(output_path, page_size: "A4") do |pdf|
      data.each_with_index do |item, index|
        # Start a new page for each QR code (except the first one)
        pdf.start_new_page if index > 0

        # Add title (small for stickers)
        pdf.font_size(8)
        pdf.text item[:title], align: :center, style: :bold
        pdf.move_down 5

        # Generate QR code
        qr_code = RQRCode::QRCode.new(item[:url])

        # Convert QR code to PNG data (maximized for A4)
        qr_size = 500  # Much larger QR code
        png = qr_code.as_png(
          bit_depth: 1,
          border_modules: 2,
          color_mode: ChunkyPNG::COLOR_GRAYSCALE,
          color: "black",
          file: nil,
          fill: "white",
          module_px_size: 8,
          resize_exactly_to: false,
          resize_gte_to: qr_size,
          size: qr_size
        )

        # Calculate centered position for QR code
        x_position = pdf.bounds.left + (pdf.bounds.width - qr_size) / 2
        # y_position = pdf.bounds.top - 50 - qr_size  # 50px from top for title space
        y_position = pdf.bounds.top - 100

        # Add QR code image to PDF (centered and maximized)
        pdf.image StringIO.new(png.to_s),
          at: [x_position, y_position],
          width: qr_size,
          height: qr_size

        # Position URL text at bottom of page (very small for debugging)
        pdf.move_cursor_to 30  # 30px from bottom
        pdf.font_size(6)
        pdf.text item[:url], align: :center, color: "AAAAAA"
      end
    end

    puts "PDF generated successfully at: #{output_path}"
    output_path
  end
end
