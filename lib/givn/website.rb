require 'httparty'
require 'http-cookie'
require 'json'
require 'fileutils'
require 'oga'
require 'date'
require_relative 'string'

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
        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language' => 'en-US,en;q=0.5',
        'Accept-Encoding' => 'gzip;q=1.0,deflate;q=0.6,identity',
        'Cookie' => to_cookie_string(uri),
        'Content-Type' => 'application/x-www-form-urlencoded',
        'User-Agent' => ua
      }, body: URI.encode_www_form(data))

      raise "status #{response.code}" if response.code >= 400

      parse_cookie(response)

      # parse admin page
      nil
    end

    def orders(slug, page = 1)
      result = []
      loop do
        # puts "Loading page #{page}"
        uri = "/admin/#{slug}/orders?page=#{page}"

        response = self.class.get(uri, headers: {
          'Connection' => 'keep-alive',
          'Accept' => '*/*',
          'Accept-Language' => 'en-US,en;q=0.5',
          'Cookie' => to_cookie_string(uri),
          'User-Agent' => ua
        })
        parse_cookie(response)

        doc = Oga.parse_html(response.body)

        #puts response.body

        data = doc.xpath("//main//a")

        has_next = false
        orders = data.map do |order_data|
          has_next ||= order_data.text.strip == "Next"
          next if order_data.xpath("div").empty?
          # "/admin/bonitacafe/orders/b432d1b7-0d93-4274-8985-eca3f0fc9b54"
          url = order_data.attribute("href").value
          # 16. May 2023
          date = order_data.xpath("div")[0].xpath("div")[0].xpath("div")[0].text
          time = order_data.xpath("div")[0].xpath("div")[0].xpath("div")[1].text
          description1 = order_data.xpath("div")[0].xpath("div")[1].xpath("div")[0].text.strip
          description2 = order_data.xpath("div")[0].xpath("div")[1].xpath("div")[1].text.strip
          price = order_data.xpath("div")[0].xpath("div")[2].xpath("div")[0].text.strip.gsub(/NOK[[:space:]]/, "").no_to_en_f
          { 
            date: date,
            time: time,
            timestamp: DateTime.parse("#{date} #{time}"),
            description1: description1,
            description2: description2,
            price: price
          }
        end.reject{|o| o.nil?}
        # puts orders.to_json
        result += orders
        break unless has_next
        page += 1
      end
      result.flatten
    end

    def used_codes(slug, page = 1)
      result = []
      loop do
        # puts "Loading page #{page}"
        uri = "/admin/#{slug}/used_codes?page=#{page}"

        response = self.class.get(uri, headers: {
          'Connection' => 'keep-alive',
          'Accept' => '*/*',
          'Accept-Language' => 'en-US,en;q=0.5',
          'Cookie' => to_cookie_string(uri),
          'User-Agent' => ua
        })
        parse_cookie(response)

        doc = Oga.parse_html(response.body)

        #puts response.body

        # skip header
        data =  doc.xpath("//main/div/div/div/div | //main/div/div/div/a")

        # skip non data lines
        data = data.select { |i| i.xpath("div").count > 0 }

        has_next = false
        codes = data.map do |code_data|
          has_next ||= code_data.text.strip == "Next"
          next if code_data.xpath("div").empty?

          #puts code_data.to_s
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
          price = code_data.xpath("div")[2].text.strip.gsub(/NOK[[:space:]]/, "").no_to_en_f
          { 
            date: date,
            time: time,
            timestamp: DateTime.parse("#{date} #{time}"),
            description1: description1,
            description2: description2,
            price: price
          }
        end.reject{|o| o.nil?}
        # puts codes.to_json
        result += codes
        break unless has_next
        page += 1
      end
      result.flatten
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
      path = File.expand_path("~/.givn/givn.yaml")
      require 'fileutils'
      FileUtils.mkdir_p(File.dirname(path))
      path
    end
  end
end 
