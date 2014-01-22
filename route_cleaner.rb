#!/usr/bin/env ruby

require "ap"
require "csv"
require "geocoder"
require "optparse"

# Calculate distance between two points in miles
def distance(point_1, point_2)
  distance = Geocoder::Calculations.distance_between(point_1, point_2)
  distance.round(2)
end

# Calculate time taken to travel between two points in seconds
def duration(start_time, finish_time)
  finish_time - start_time
end

# Calculate speed required to travel between two points in MPH
def speed(distance, duration)
  (distance / (duration / 3600)).round(2)
end

# Calculate acceleration between two points in miles per hour, per second
def acceleration(velocity_1, velocity_2, duration)
  ((velocity_2 - velocity_1) / duration).round(2)
end

# Get info on each individual journey segment
def segments_info(type, data)
  counter = 0
  segments_info = []

  data.each do
    # Get data for each segment
    if type == "distance"
      segment = distance(data[counter], data[counter + 1])
    elsif type == "duration"
      segment = duration(data[counter], data[counter + 1])
    end
    segments_info << segment
    # Increment as long as next value for comparison exists
    counter += 1 if counter < @journey.length - 2
  end

  # Return array with each segment's data
  segments_info
end

# Get speed for each journey segment
def segments_mph
  # Get distance and duration data info for individual segments
  segments_distance = segments_info("distance", @points)
  segments_duration = segments_info("duration", @times)

  # Combine distance and duration for each segment into array
  dist_and_dur = segments_distance.zip(segments_duration)

  # Get speed required to reach point
  segments_mph = dist_and_dur.map do |dist, dur|
    speed(dist, dur)
  end

  # Return array with each segment's speed
  segments_mph
end

# Get acceleration for each journey segment
def segments_acceleration
  counter = 0
  segments_acceleration = []

  @journey.each do |point|
    # Assign velocity variables
    point == @journey.first ? velocity_1 = 0 : velocity_1 = point["mph"]
    velocity_2 = @journey[counter+1]["mph"]
    # Get segment acceleration
    segment = acceleration(velocity_1, velocity_2, point["duration"])
    segments_acceleration << segment
    # Increment as long as next value for comparison exists
    counter += 1 if counter < @journey.length - 2
  end

  # Return array with each segment's acceleration
  segments_acceleration
end

# Create new key in each journey point hash
def add_info_to_journey(key)
  counter = 0

  if key == "mph"
    value = segments_mph
  elsif key == "duration"
    value = segments_info("duration", @times)
  elsif key == "acceleration"
    value = segments_acceleration
  end

  @journey.each do |point|
    point[key] = value[counter]
    counter += 1
  end
end

# Discard potentially erroneous points from journey
def clean_route
  add_info_to_journey("mph")
  add_info_to_journey("duration")
  add_info_to_journey("acceleration")

  clean_points = []

  # First discard points that would require exceeding max journey speed to reach
  # (70mph default, could be adjusted if journey took place solely within
  # urban area etc.) or if actual speed limit data was available

  # Then discard points with implausible acceleration or deceleration
  # (defaults are 10 and -15 respectively)
  # My assumptions are based on the fact a Porsche 911 has values of around
  # 16 and -24, so I've modified my estimates accordingly :)
  @journey.each do |point|
    speed = point["mph"]
    acc = point["acceleration"]
    # If max speed, max acceleration or max deceleration exceeded,
    # consider point potentially erroneous
    unless speed > @max_speed || acc > @max_acc || acc < @max_dec
      clean_points << point
    end
  end

  # Remove (now unnecessary) key/value pairs from each point
  clean_points.each do |point|
    point.delete_if do |key, value|
      key == "mph" || key == "duration" || key == "acceleration"
    end
  end

  # Convert clean points to array
  clean_points = clean_points.map { |point| point.values }

  # Return clean points array
  clean_points
end

# Hash to hold command line options parsed by OptionParser
options = {}

optparse = OptionParser.new do |opts|
  # Set banner to display at the top of the help screen
  opts.banner = "Usage: ./route_cleaner.rb [options] file.csv"

  # Define the options, and what they do
  options[:max_speed] = 70
  opts.on( "-s", "--max-speed MPH", "Set a maximum journey speed" ) do |mph|
    options[:max_speed] = mph
  end

  options[:max_acceleration] = 10
  opts.on( "-a", "--max-acc VALUE", "Set a maximum acceleration" ) do |value|
    options[:max_acceleration] = value
  end

  options[:max_deceleration] = -15
  opts.on( "-d", "--max-dec VALUE", "Set a maximum deceleration" ) do |value|
    options[:max_deceleration] = value
  end

  options[:logfile] = nil
  opts.on( "-l", "--logfile FILE", "Log output to FILE" ) do |file|
    options[:logfile] = file
  end

  # Display the help screen
  opts.on( "-h", "--help", "Display this screen" ) do
    puts opts
    exit
  end
end

# Parse command line input
optparse.parse!

ARGV.each do |file|
  puts "Reading file #{file}..."
  sleep(0.5)
  # Raise error if data file is either missing or not .csv format
  if file.nil?
    raise OptionParser::MissingArgument
  elsif !file.include?(".csv")
    raise OptionParser::InvalidArgument
  else
    # Read data from file
    @file = CSV.read(file)
  end
end

# Set max speed, acceleration and deceleration
@max_speed = options[:max_speed].to_i
@max_acc = options[:max_acceleration].to_i
@max_dec = options[:max_deceleration].to_i

# Convert data to array of hashes
@journey = @file.map do |row|
  Hash["lat", row[0], "lon", row[1], "timestamp", row[2]]
end

# Store all lat/long points in array
@points = @journey.map do |point|
  arr = []
  arr << point["lat"]
  arr << point["lon"]
end

# Store all times in array
@times = @journey.map do |point|
  Time.at(point["timestamp"].to_i)
end

# Get clean route
route = clean_route

if options[:logfile]
  # Make sure output is .csv format
  options[:logfile] += ".csv" if !options[:logfile].include?(".csv")

  # Generate new .csv file
  CSV.open(options[:logfile], "wb") do |csv|
    route.each { |point| csv << point }
  end

  puts "Logging output to #{options[:logfile]}"
  sleep(0.5)
  puts "Successfully created #{options[:logfile]}"
else
  # Print clean route
  ap route
end
