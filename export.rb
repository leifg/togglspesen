require 'dotenv'
require 'httparty'
require 'date'

Dotenv.load

year, month = ARGV.map(&:to_i)

year ||= Time.now.year
month ||= Time.now.month

# Get base data from Toggl
class TogglApi
  include HTTParty
  base_uri 'https://www.toggl.com/api/v8'

  def initialize(api_token)
    @api_token = api_token
    @options = {
      headers: { 'Content-Type' => 'application/json' },
      basic_auth: { username: @api_token, password: 'api_token' }
    }
  end

  def workspace_id
    self.class.get('/workspaces', @options).parsed_response.first['id']
  end
end

# Get reports from Toggl
class TogglReportApi
  include HTTParty
  base_uri 'https://www.toggl.com/reports/api/v2'

  attr_reader :api_token
  attr_reader :month
  attr_reader :year
  attr_reader :options

  def initialize(api_token, month, year)
    @api_token = api_token
    @month = month
    @year = year
    @options = {
      headers: { 'Content-Type' => 'application/json' },
      basic_auth: { username: @api_token, password: 'api_token' }
    }
  end

  def time_entries
    wid = TogglApi.new(api_token).workspace_id
    gathered = []
    page = 1
    loop do
      cur_data = self.class.get(
        '/details', options.merge(query: query(wid, page))
      ).parsed_response['data']
      page += 1
      gathered += cur_data.select { |t| t['tags'].include?('on location') }
      break if cur_data.empty?
    end

    gathered
  end

  private

  def query(wid, page)
    {
      user_agent: 'togglspesen',
      workspace_id: wid,
      page: page,
      since: "#{year}-#{month}-01",
      until: "#{year}-#{month}-#{last_day_of_month}",
      tags: 'on location'
    }
  end

  def last_day_of_month
    Date.civil(year,month,-1).day
  end
end

def map_entries(time_entries)
  start_entry = time_entries.min_by{|t| t['start']}
  start_time = DateTime.parse(start_entry['start'])
  end_time = DateTime.parse(time_entries.max_by{|t| t['end']}['end'])
  {
    start: start_time,
    end: end_time,
    client: start_entry['client']
  }
end

def group_by_date(toogl_result)
  toogl_result
    .sort_by{|t| t['start']}
    .group_by{|t| t['start'][/^(\d{4}-\d{2}-\d{2})/]}
    .inject({}) do |acc, (day, time_entries)|
      acc.merge!(day => map_entries(time_entries))
    end
end

def only_time(date)
  hour = date.hour.to_s.rjust(2, '0')
  minute = date.minute.to_s.rjust(2, '0')
  "#{hour}:#{minute}"
end

def remove_seconds_from_date(date)
  date.to_time.to_i / 60 * 60
end

def duration(start_time, end_time)
  format_duration(remove_seconds_from_date(end_time) - remove_seconds_from_date(start_time))
end

def format_duration(duration)
  total_minutes = duration.to_i / 60
  hours = (total_minutes / 60).to_s.rjust(2, '0')
  minutes = (total_minutes % 60).to_s.rjust(2, '0')
  "#{hours}:#{minutes}"
end

result = TogglReportApi.new(ENV['TOGGL_API_TOKEN'], month, year).time_entries

$stdout.puts 'Datum,Anfang,Ende,Dauer,Kunde'
group_by_date(result).each do |day, data|
  $stdout.puts "#{day},#{only_time(data[:start])},#{only_time(data[:end])},#{duration(data[:start], data[:end])},#{data[:client]}"
end
