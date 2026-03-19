require 'net/http'
require 'uri'
require 'json'

module EmailHelper
  BREVO_API_URL = 'https://api.brevo.com/v3/smtp/email'

  def self.send_receipt(order)
    return unless ENV['BREVO_API_KEY'] && order.customer_email

    uri = URI.parse(BREVO_API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.request_uri)
    request['api-key'] = ENV['BREVO_API_KEY']
    request['Content-Type'] = 'application/json'
    request['Accept'] = 'application/json'

    html_content = generate_receipt_html(order)

    request.body = {
      sender: { 
        name: ENV['SENDER_NAME'] || "Antivoid Shop", 
        email: ENV['SENDER_EMAIL'] || "noreply@antivoid.shop" 
      },
      to: [{ email: order.customer_email, name: order.customer_name }],
      subject: "Struk Pembelian ##{order.id} - Antivoid Shop",
      htmlContent: html_content
    }.to_json

    response = http.request(request)
    
    unless response.code == '201'
      puts "Brevo Email Error: #{response.body}"
    end
    
    response.code == '201'
  end

  def self.send_admin_order_notification(order, base_url = "https://antivoid-ecom.up.railway.app")
    unless ENV['BREVO_API_KEY'] && ENV['ADMIN_EMAIL']
      puts "ADMIN NOTIFICATION SKIPPED: BREVO_API_KEY or ADMIN_EMAIL missing in ENV"
      return
    end

    uri = URI.parse(BREVO_API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.request_uri)
    request['api-key'] = ENV['BREVO_API_KEY']
    request['Content-Type'] = 'application/json'
    request['Accept'] = 'application/json'

    request.body = {
      sender: { 
        name: "Antivoid System", 
        email: ENV['SENDER_EMAIL'] || "system@antivoid.shop" 
      },
      to: [{ email: ENV['ADMIN_EMAIL'], name: "Admin Antivoid" }],
      subject: "🚨 [#{order.payment_method}] PESANAN BARU: ##{order.id}",
      htmlContent: "
        <h3>Halo Admin,</h3>
        <p>Ada pesanan baru dari <strong>#{order.customer_name}</strong> dengan metode <strong>#{order.payment_method}</strong> sebesar <strong>Rp #{order.total_price.to_s.gsub(/\B(?=(\d{3})+(?!\d))/, '.')}</strong>.</p>
        <p><a href='#{base_url}/admin/orders/view?id=#{order.id}'>Klik di sini untuk melihat detail pesanan di Dashboard Admin.</a></p>
      "
    }.to_json

    response = http.request(request)
    puts "ADMIN NOTIFICATION SENT: Status #{response.code} - Body: #{response.body[0..100]}..."
    
    unless response.code == '201'
      puts "Brevo Admin Email Error: #{response.body}"
    end
  rescue StandardError => e
    puts "Admin email notification failed: #{e.message}"
  end

  private

  def self.generate_receipt_html(order)
    items_html = order.items.map do |item|
      "<tr>
        <td style='padding: 10px; border-bottom: 1px solid #eee;'>#{item[:product]&.name || 'Produk'}</td>
        <td style='padding: 10px; border-bottom: 1px solid #eee; text-align: center;'>#{item[:quantity]}</td>
        <td style='padding: 10px; border-bottom: 1px solid #eee; text-align: right;'>Rp #{item[:price].to_s.gsub(/\B(?=(\d{3})+(?!\d))/, ".")}</td>
      </tr>"
    end.join

    "<html>
      <body style='font-family: Arial, sans-serif; color: #333; line-height: 1.6;'>
        <div style='max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #ddd; border-radius: 10px;'>
          <h2 style='color: #4f46e5; text-align: center;'>Terima Kasih Atas Pesanan Anda!</h2>
          <p>Halo <strong>#{order.customer_name}</strong>,</p>
          <p>Pesanan Anda telah diterima dan sedang kami proses. Berikut adalah detail pesanan Anda:</p>
          
          <table style='width: 100%; border-collapse: collapse; margin: 20px 0;'>
            <thead>
              <tr style='background: #f8fafc;'>
                <th style='padding: 10px; text-align: left; border-bottom: 2px solid #e2e8f0;'>Produk</th>
                <th style='padding: 10px; text-align: center; border-bottom: 2px solid #e2e8f0;'>Qty</th>
                <th style='padding: 10px; text-align: right; border-bottom: 2px solid #e2e8f0;'>Harga</th>
              </tr>
            </thead>
            <tbody>
              #{items_html}
            </tbody>
            <tfoot>
              <tr>
                <td colspan='2' style='padding: 10px; font-weight: bold; text-align: right;'>Total Akhir</td>
                <td style='padding: 10px; font-weight: bold; text-align: right; color: #4f46e5;'>Rp #{order.total_price.to_s.gsub(/\B(?=(\d{3})+(?!\d))/, ".")}</td>
              </tr>
            </tfoot>
          </table>
          
          <div style='background: #f1f5f9; padding: 15px; border-radius: 8px; margin-top: 20px;'>
            <p style='margin: 0;'><strong>Alamat Pengiriman:</strong><br>#{order.address}</p>
          </div>
          
          <p style='font-size: 12px; color: #64748b; margin-top: 30px; text-align: center;'>
            Antivoid E-Commerce &copy; 2026. Seluruh Hak Cipta Dilindungi.<br>
            Jika ada pertanyaan, hubungi kami via WhatsApp.
          </p>
        </div>
      </body>
    </html>"
  end
end
