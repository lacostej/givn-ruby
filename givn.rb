require_relative 'lib/givn/website'

def dump_orders_codes(outlet, from, to)
  venue_slug = JSON.parse(File.read(".env.#{outlet}.json"))['slug']
  puts "ORDERS from #{from} to #{to}"
  website_client.orders(venue_slug).select{|order| order[:timestamp] >= from and order[:timestamp] < to}.each do |order|
    puts "#{order[:timestamp].strftime("%Y-%m-%d %H:%M")}\t#{order[:price]}\n\t#{order[:description1]}\n\t#{order[:description2]}"
  end
  puts "CODES from #{from} to #{to}"
  website_client.used_codes(venue_slug).select{|code| code[:timestamp] >= from and code[:timestamp] < to}.each do |code|
    puts "#{code[:timestamp].strftime("%Y-%m-%d %H:%M")}\t#{code[:price]}\n\t#{code[:description1]}\n\t#{code[:description2]}"
  end
end

def website_client
  @website_client ||= begin
    client = Givn::Website.new
    credentials = JSON.parse(File.read("credentials.json"), symbolize_names: true)
    client.login(**credentials)
    client
  end
end

now = Time.now
year = now.year
month = now.month
day = now.day

outlets = [:cafe, :dlc]
outlet = ARGV[0].to_sym
raise "missing outlet arg. Use one in: #{outlets.join(',')}" unless outlets.include? outlet


transaction_day = Date.new(year, month, day)
#if now.hour < 11
#  transaction_day -= 1
#end

case ARGV[1]
when "today"
  from_date = transaction_day
  to_date = transaction_day + 1

  dump_orders_codes(outlet, from_date, to_date)

when /^[0-9][0-9][0-9][0-9]-[0-9][0-9](_[0-9][0-9][0-9][0-9]-[0-9][0-9])?$/
  first_last_month = ARGV[0].split("_")
  transaction_month = Date.strptime(first_last_month[0],"%Y-%m")
  last_transaction_month = first_last_month.count > 1 ? Date.strptime(first_last_month[1],"%Y-%m") : transaction_month

  files = []
  loop do
    from = Date.new(transaction_month.year, transaction_month.month, 1)
    to = Date.new(transaction_month.year, transaction_month.month, -1)

    dump_orders_codes(outlet, from, to)

    if transaction_month.month + 1 > 12
      transaction_month = Date.new(transaction_month.year + 1, 1, 1)
    else
      transaction_month = Date.new(transaction_month.year, transaction_month.month + 1, 1)
    end

    break if last_transaction_month < transaction_month
  end
when "year"
  files = []
  (1..month).each do |month|
    from = Date.new(year, month, 1)
    to = Date.new(year, month, -1)
    dump_orders_codes(outlet, from, to)
  end
when "previousmonth"
  if (month == 1)
    year = year - 1
    month = 12
  else
    month = month - 1
  end
  from = Date.new(year, month , 1)
  to = Date.new(year, month , -1)
  dump_orders_codes(outlet, from, to)
when "month"
  from = Date.new(year, month, 1)
  to = Date.new(year, month, day)
  dump_orders_codes(outlet, from, to)
when "lastweek"
  from = transaction_day - transaction_day.wday - 7
  to = transaction_day - transaction_day.wday

  dump_orders_codes(outlet, from, to)
when "week"
  from = transaction_day - transaction_day.wday + 1
  to = Date.new(year, month, day)
  dump_orders_codes(outlet, from, to)
else
  raise "Missing argument (today|month|previousmonth|year)"
end