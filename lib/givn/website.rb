require 'httparty'
require 'http-cookie'
require 'json'
require 'fileutils'
require 'oga'
require 'date'

module Givn
  class Website
    include HTTParty
    base_uri 'https://givn.no'    
    #debug_output

    def initialize
      @cookie_jar = HTTP::CookieJar.new
      @cookie_jar.load(cookies_filename) if File.exist? cookies_filename
    end

    def login(username:, password: )
      uri = "/users/login"
      response = self.class.get(uri, headers: {})
      parse_cookie(response)

      # <meta content="Jg82IjdCAzA5FzENRysqLVdSJiURYCxkGHRNv7iVlGz56jdU16mAB5TS" name="csrf-token">
      body = response.body
      doc = Oga.parse_html(body)
      csrf = doc.xpath("/html/head/meta[@name = 'csrf-token']").first
      raise "Missing csrf\n#{body}" unless csrf
      @csrf_token = csrf.attributes.find{|a| a.name == 'content'}.value

      data = {
        '_csrf_token' => @csrf_token,
        'user[email]' => username,
        'user[password]' => password,
        'user[remember_me]' => 'true'
      }

      response = self.class.post(uri, headers: {
        'Connection' => 'keep-alive',
        'Accept' => '*/*',
        'Accept-Language' => 'en-US,en;q=0.5',
        'Cookie' => to_cookie_string(uri),
        #'Content-Type' => 'application/x-www-form-urlencoded',
        'User-Agent' => ua
      }, body: URI.encode_www_form(data))
      parse_cookie(response)

      # parse admin page
      nil
    end

    def orders(slug)
      uri = "/admin/#{slug}/orders"
      response = self.class.get(uri, headers: {
        'Connection' => 'keep-alive',
        'Accept' => '*/*',
        'Accept-Language' => 'en-US,en;q=0.5',
        'Cookie' => to_cookie_string(uri),
        'User-Agent' => ua
      })
      parse_cookie(response)

      doc = Oga.parse_html(response.body)

      data = doc.xpath("//main//a")

      data.map do |order_data|
        # "/admin/bonitacafe/orders/b432d1b7-0d93-4274-8985-eca3f0fc9b54"
        url = order_data.attribute("href").value
        # 16. May 2023
        date = order_data.xpath("div")[0].xpath("div")[0].xpath("div")[0].text
        time = order_data.xpath("div")[0].xpath("div")[0].xpath("div")[1].text
        description1 = order_data.xpath("div")[0].xpath("div")[1].xpath("div")[0].text.strip
        description2 = order_data.xpath("div")[0].xpath("div")[1].xpath("div")[1].text.strip
        price = order_data.xpath("div")[0].xpath("div")[2].xpath("div")[0].text.strip.gsub(/NOK[[:space:]]/, "").to_f
        { 
          date: date,
          time: time,
          timestamp: DateTime.parse("#{date} #{time}"),
          description1: description1,
          description2: description2,
          price: price
        }
      end
    end

    def used_codes(slug)
      uri = "/admin/#{slug}/used_codes"

      response = self.class.get(uri, headers: {
        'Connection' => 'keep-alive',
        'Accept' => '*/*',
        'Accept-Language' => 'en-US,en;q=0.5',
        'Cookie' => to_cookie_string(uri),
        'User-Agent' => ua
      })
      parse_cookie(response)

      doc = Oga.parse_html(response.body)

      # skip header
      data =  doc.xpath("//main/div/div/div/div | //main/div/div/div/a")

      # skip non data lines
      data = data.select { |i| i.xpath("div").count > 0 }

      data.map do |code_data|
        # data[0].xpath("div").count
        # "/admin/bonitacafe/orders/b432d1b7-0d93-4274-8985-eca3f0fc9b54"
        url = code_data.name == "a" ? code_data.attribute("href").value : nil
        # 16. May 2023
        date = code_data.xpath("div")[0].xpath("div")[0].text
        time = code_data.xpath("div")[0].xpath("div")[1].text
        # returns "Gavekort Bonita Cafe / De La Casa 300kr" 
        description1 = code_data.xpath("div")[1].xpath("div")[0].text.strip
        # returns "oppvakt-flyndre-134a Y7KJ" 
        description2 = code_data.xpath("div")[1].xpath("div")[1].text.strip.gsub("\n", "").gsub(/ +/, " ")
        price = code_data.xpath("div")[2].text.strip.gsub(/NOK[[:space:]]/, "").to_f
        { 
          date: date,
          time: time,
          timestamp: DateTime.parse("#{date} #{time}"),
          description1: description1,
          description2: description2,
          price: price
        }
      end
      #response.body.
    end

    def to_cookie_string(uri)
      absolute_uri = uri.start_with?("/") ? self.class.base_uri + uri : uri
      HTTP::Cookie.cookie_value(@cookie_jar.cookies(absolute_uri))
    end

    def ua
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:96.0) Gecko/20100101 Firefox/96.0'
    end

    def parse_cookie(response)
      cookies = (response.get_fields('Set-Cookie') || [])
      if cookies.count > 0
        uri = response.request.uri
        #puts "\nNew cookies for #{uri}:"
        cookies.each do |c| 
          #puts "\t#{c}"
          @cookie_jar.parse(c, uri) 
        end
        @cookie_jar.save(cookies_filename)
      end
    end

    def cookies_filename
      path = File.expand_path("~/.lightspeed/lightspeed.yaml")
      require 'fileutils'
      FileUtils.mkdir_p(File.dirname(path))
      path
    end
  end
end 
