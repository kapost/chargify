module Chargify
  class << self
     attr_accessor :subdomain, :api_key, :shared_key, :site#, :format, :timeout, :shared_key

     def configure
       yield self
       
       self.site ||= "https://#{subdomain}.chargify.com"
       
     end
     
     def client
       @client ||= Client.new
     end
     
     def method_missing(id, *args, &block)
       if client.respond_to?(id)
         client.send(id, *args, &block)
       else
         raise Exception.new("unsupported method #{id}")
       end
     end
   end
 
  class UnexpectedResponseError < RuntimeError
  end
  
  class Parser < HTTParty::Parser
    def parse
      return {} if body.strip.empty?

      begin
        ::JSON.parse(body) || {}
      rescue JSON::ParserError => e
        raise UnexpectedResponseError, "Could not parse JSON: #{e.message}. Chargify's raw response: #{body}"
      end
    end
  end
  
  class Client
    include HTTParty
    ssl_version :TLSv1
    
    parser Chargify::Parser
    headers 'Content-Type' => 'application/json' 
    
    attr_reader :api_key, :subdomain
    
    # Your API key can be generated on the settings screen.
    def initialize(api_key=nil, subdomain=nil)
      api_key ||= Chargify.api_key
      subdomain ||= Chargify.subdomain
      
      self.class.base_uri "https://#{subdomain}.chargify.com"
      self.class.basic_auth api_key, 'x'
      
    end
    
    # options: page
    def list_customers(options={})
      customers = get("/customers.json", :query => options)
      customers.map{|c| Hashie::Mash.new c['customer']}
    end
    
    def customer_by_id(chargify_id)
      request = get("/customers/#{chargify_id}.json")
      success = request.code == 200
      response = Hashie::Mash.new(request).customer if success
      Hashie::Mash.new(response || {}).update(:success? => success)
    end
    
    def customer_by_reference(reference_id)
      request = get("/customers/lookup.json?reference=#{reference_id}")
      success = request.code == 200
      response = Hashie::Mash.new(request).customer if success
      Hashie::Mash.new(response || {}).update(:success? => success)
    end
    
    alias customer customer_by_reference
    
    
    #
    # * first_name (Required)
    # * last_name (Required)
    # * email (Required)
    # * organization (Optional) Company/Organization name
    # * reference (Optional, but encouraged) The unique identifier used within your own application for this customer
    # 
    def create_customer(info={})
      response = Hashie::Mash.new(post("/customers.json", :body => {:customer => info}))
      return response.customer if response.customer
      response
    end
    
    #
    # * first_name (Required)
    # * last_name (Required)
    # * email (Required)
    # * organization (Optional) Company/Organization name
    # * reference (Optional, but encouraged) The unique identifier used within your own application for this customer
    # 
    def update_customer(customer_id, info={})
      info.stringify_keys!
      response = Hashie::Mash.new(put("/customers/#{customer_id}.json", :body => {:customer => info}))
      return response.customer unless response.customer.to_a.empty?
      response
    end
    
    def customer_subscriptions(chargify_id)
      subscriptions = get("/customers/#{chargify_id}/subscriptions.json")
      subscriptions.map{|s| Hashie::Mash.new s['subscription']}
    end
    
    def subscription(subscription_id)
      raw_response = get("/subscriptions/#{subscription_id}.json")
      return nil if raw_response.code != 200
      Hashie::Mash.new(raw_response).subscription
    end
    
    # Returns all elements outputted by Chargify plus:
    # response.success? -> true if response code is 201, false otherwise
    def create_subscription(subscription_attributes={})
      raw_response = post("/subscriptions.json", :body => {:subscription => subscription_attributes})
      created  = true if raw_response.code == 201
      response = Hashie::Mash.new(raw_response)
      (response.subscription || response).update(:success? => created)
    end

    # Returns all elements outputted by Chargify plus:
    # response.success? -> true if response code is 200, false otherwise
    def update_subscription(sub_id, subscription_attributes = {})
      raw_response = put("/subscriptions/#{sub_id}.json", :body => {:subscription => subscription_attributes})
      updated      = true if raw_response.code == 200
      response     = Hashie::Mash.new(raw_response)
      (response.subscription || response).update(:success? => updated)
    end
    
    # Returns all elements outputted by Chargify plus:
    # response.success? -> true if response code is 200, false otherwise
    def reset_balance(sub_id)
      raw_response = put("/subscriptions/#{sub_id}/reset_balance.json", :body => "")
      updated      = true if raw_response.code == 200
      response     = Hashie::Mash.new(raw_response) rescue Hashie::Mash.new
      (response.subscription || response).update(:success? => updated)
    end

    # Returns all elements outputted by Chargify plus:
    # response.success? -> true if response code is 200, false otherwise
    def cancel_subscription(sub_id, message="")
      raw_response = delete("/subscriptions/#{sub_id}.json", :body => {:subscription => {:cancellation_message => message} })
      deleted      = true if raw_response.code == 200
      response     = Hashie::Mash.new(raw_response)
      (response.subscription || response).update(:success? => deleted)
    end

    def reactivate_subscription(sub_id)
      raw_response = put("/subscriptions/#{sub_id}/reactivate.json", :body => "")
      reactivated  = true if raw_response.code == 200
      response     = Hashie::Mash.new(raw_response) rescue Hashie::Mash.new
      (response.subscription || response).update(:success? => reactivated)
    end
      
    def charge_subscription(sub_id, subscription_attributes={})
      raw_response = post("/subscriptions/#{sub_id}/charges.json", :body => { :charge => subscription_attributes })
      success      = raw_response.code == 201
      if raw_response.code == 404
        raw_response = {}
      end

      response = Hashie::Mash.new(raw_response)
      (response.charge || response).update(:success? => success)
    end
    
    def migrate_subscription(sub_id, product_id)
      raw_response = post("/subscriptions/#{sub_id}/migrations.json", :body => {:product_id => product_id })
      success      = true if raw_response.code == 200
      response     = Hashie::Mash.new(raw_response)
      (response.subscription || response).update(:success? => success)
    end

    def migrate_subscription_by_handle(sub_id, product_handle)
      raw_response = post("/subscriptions/#{sub_id}/migrations.json", :body => {:product_handle => product_handle })
      success      = true if raw_response.code == 200
      response     = Hashie::Mash.new(raw_response)
      (response.subscription || {}).update(:success? => success)
    end

    def adjust_subscription(sub_id, attributes = {})
      raw_response = post("/subscriptions/#{sub_id}/adjustments.json",
                          :body => { :adjustment => attributes })
      created = true if raw_response.code == 201
      response = Hashie::Mash.new(raw_response)
      (response.adjustment || response).update(:success? => created)
    end

    def list_products
      products = get("/products.json")
      products.map{|p| Hashie::Mash.new p['product']}
    end
    
    def product(product_id)
      Hashie::Mash.new( get("/products/#{product_id}.json")).product
    end
    
    def product_by_handle(handle)
      Hashie::Mash.new(get("/products/handle/#{handle}.json")).product
    end
    
    def list_subscription_usage(subscription_id, component_id)
      raw_response = get("/subscriptions/#{subscription_id}/components/#{component_id}/usages.json")
      success      = raw_response.code == 200
      response     = Hashie::Mash.new(raw_response)
      response.update(:success? => success)
    end
    
    def subscription_transactions(sub_id, options={})
      transactions = get("/subscriptions/#{sub_id}/transactions.json", :query => options)
      transactions.map{|t| Hashie::Mash.new t['transaction']}
    end

    def subscription_statements(sub_id, options={})
      statements = get("/subscriptions/#{sub_id}/statements.json", :query => options)
      statements.map{|t| Hashie::Mash.new t['statement']}
    end
    
    def subscription_statement(stmt_id)
      Hashie::Mash.new( get("/statements/#{stmt_id}.json")).statement
    end

    def site_transactions(options={})
      transactions = get("/transactions.json", :query => options)
      transactions.map{|t| Hashie::Mash.new t['transaction']}
    end

    def list_components(subscription_id)
      components = get("/subscriptions/#{subscription_id}/components.json")
      components.map{|c| Hashie::Mash.new c['component']}
    end
    
    def subscription_component(subscription_id, component_id)
      response = get("/subscriptions/#{subscription_id}/components/#{component_id}.json")
      Hashie::Mash.new(response).component
    end
    
    def update_subscription_component_allocated_quantity(subscription_id, component_id, quantity)
      update_subscription_component(subscription_id, component_id, :allocated_quantity => quantity)
    end

    def update_subscription_component_enabled(subscription_id, component_id, enabled)
      update_subscription_component(subscription_id, component_id, :enabled => enabled)
    end

    def update_subscription_component(subscription_id, component_id, component = {})
      component[:enabled] = (component[:enabled] ? 1 : 0) if component.keys.include?(:enabled)
      response = put("/subscriptions/#{subscription_id}/components/#{component_id}.json", 
                    :body => {:component => component})
      response[:success?] = response.code == 200
      Hashie::Mash.new(response)
    end 
    
    def list_product_families
      families = get("/product_families.json")
      families.map{|c| Hashie::Mash.new c['product_family']}
    end
    
    def product_family_by_handle(handle)
      response = get("/product_families/handle/#{handle}.json")
      Hashie::Mash.new(response)
    end

    alias update_metered_component  update_subscription_component_allocated_quantity
    alias update_component_quantity update_subscription_component_allocated_quantity
    alias update_on_off_component   update_subscription_component_enabled
    alias update_component          update_subscription_component

      
    private
    
      def post(path, options={})
        jsonify_body!(options)
        self.class.post(path, options)
      end
    
      def put(path, options={})
        jsonify_body!(options)
        self.class.put(path, options)
      end
    
      def delete(path, options={})
        jsonify_body!(options)
        self.class.delete(path, options)
      end
    
      def get(path, options={})
        jsonify_body!(options)
        self.class.get(path, options)
      end
    
      def jsonify_body!(options)
        options[:body] = options[:body].to_json if options[:body]
      end
  end
end
