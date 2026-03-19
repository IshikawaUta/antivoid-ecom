module ShopController
  def handle_cart_add
    product_id = @req.params['product_id']
    quantity = @req.params['quantity'].to_i
    
    product = Product.find(product_id)
    if product && product.stock > 0 && quantity > 0
      @req.session['cart'] ||= {}
      
      current_qty = @req.session['cart'][product_id] || 0
      if current_qty + quantity <= product.stock
        @req.session['cart'][product_id] = current_qty + quantity
      else
        @req.session['cart'][product_id] = product.stock
      end
    end
    
    referer = @req.env['HTTP_REFERER'] || '/shop'
    redirect_to(referer)
  end

  def handle_cart_remove
    product_id = @req.params['id']
    @req.session['cart']&.delete(product_id)
    redirect_to('/cart')
  end

  def handle_cart_update
    product_id = @req.params['product_id']
    quantity = @req.params['quantity'].to_i
    if quantity > 0
      @req.session['cart'][product_id] = quantity
    else
      @req.session['cart']&.delete(product_id)
    end
    redirect_to('/cart')
  end

  def handle_checkout
    cart = @req.session['cart'] || {}
    return redirect_to('/shop') if cart.empty?

    items = []
    total = 0
    cart.each do |id, qty|
      product = Product.find(id)
      if product && product.stock >= qty
        items << { product_id: product.id, name: product.name, price: product.price, quantity: qty }
        total += product.price * qty
      end
    end

    if items.any?
      user = AuthHelper.current_user(@req)
      order_data = {
        customer_name: @req.params['customer_name'] || @req.params['name'],
        contact: @req.params['contact'] || @req.params['whatsapp'],
        customer_email: @req.params['customer_email'],
        address: @req.params['address'],
        items: items,
        total_price: total,
        user_id: user ? user.id.to_s : nil
      }
      
      # Real-time Stock Check before finalizing
      can_process = true
      items.each do |item|
        current_product = Product.find(item[:product_id].to_s)
        if !current_product || current_product.stock < item[:quantity]
          can_process = false
          break
        end
      end

      unless can_process
        return redirect_to('/cart')
      end

      # Actually deduct stock
      items.each do |item|
        product = Product.find(item[:product_id].to_s)
        Product.update(item[:product_id].to_s, { stock: product.stock - item[:quantity] })
      end
      
      order_data[:payment_method] = @req.params['payment'] || 'Manual'
      result = Order.create(order_data)
      
      # Xendit Invoice Creation (only if Gateway selected)
      if result && result.inserted_id && order_data[:payment_method] == 'Gateway'
        order = Order.find(result.inserted_id.to_s)
        invoice = XenditHelper.create_invoice(order, @req.base_url)
        
        if invoice && invoice['invoice_url']
          @req.session['cart'] = {}
          return redirect_to(invoice['invoice_url'])
        end
      end

      # Fallback for Manual or if Xendit fails
      if order_data[:payment_method] == 'Manual'
        require_relative '../utils/email_helper'
        order = Order.find(result.inserted_id.to_s)
        if order
          EmailHelper.send_receipt(order)
          EmailHelper.send_admin_order_notification(order, @req.base_url)
        end
      end

      @req.session['cart'] = {}
      redirect_to('/order-success?id=' + (result.inserted_id.to_s rescue ''))
    else
      redirect_to('/cart')
    end
  end

  def handle_xendit_webhook
    puts "DEBUG: Xendit Webhook Received - Headers: #{@req.env['HTTP_X_CALLBACK_TOKEN']}"
    unless XenditHelper.verify_callback(@req.env['HTTP_X_CALLBACK_TOKEN'])
      puts "DEBUG: Xendit Webhook Forbidden - Invalid Token"
      return [403, {}, ['Invalid Token']]
    end
    
    data = JSON.parse(@req.body.read)
    puts "DEBUG: Xendit Webhook Data: #{data['external_id']} - Status: #{data['status']}"
    external_id = data['external_id']
    status = data['status']

    if status == 'PAID' || status == 'SETTLED'
      order = Order.find(external_id)
      if order && order.status != 'Paid'
        Order.update_status(external_id, 'Paid')
        
        # Send Emails via Brevo after payment
        require_relative '../utils/email_helper'
        EmailHelper.send_receipt(order)
        EmailHelper.send_admin_order_notification(order, @req.base_url)
      end
    elsif status == 'EXPIRED'
      Order.update_status(external_id, 'Expired')
    end

    [200, { 'content-type' => 'application/json' }, [{ status: 'OK' }.to_json]]
  end

  def handle_product_review
    product_id = @req.params['product_id']
    rating = @req.params['rating'].to_i
    comment = @req.params['comment']
    user = AuthHelper.current_user(@req)

    Review.create({
      product_id: product_id,
      user_id: user.id.to_s,
      user_name: user.name,
      rating: rating,
      comment: comment
    })

    redirect_to("/product?id=#{product_id}")
  end

  def handle_wishlist_add
    product_id = @req.params['product_id']
    user = AuthHelper.current_user(@req)
    if user
      wishlist = user.wishlist || []
      unless wishlist.include?(product_id)
        wishlist << product_id
        Database.collection(:users).update_one({ _id: user.id }, { '$set' => { wishlist: wishlist } })
      end
    end
    redirect_to("/product?id=#{product_id}")
  end

  def handle_wishlist_remove
    product_id = @req.params['product_id']
    user = AuthHelper.current_user(@req)
    if user
      wishlist = user.wishlist || []
      wishlist.delete(product_id)
      Database.collection(:users).update_one({ _id: user.id }, { '$set' => { wishlist: wishlist } })
    end
    redirect_to('/account')
  end
end
