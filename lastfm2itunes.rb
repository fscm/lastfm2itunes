#!/usr/bin/ruby
#
# -*- encoding: utf-8 -*-
# coding: UTF-8
# encoding: utf-8
#
#
# == Synopsis
#
# lastfm2itunes: Update iTunes playcounts from last.fm
#
# == Requires
#
# - activesupport
# - getoptlong
# - nokogiri
# - open-uri
# - progress_bar
# - rb-appscript
# - unidecoder
#
# == Usage
#
# lastfm2itunes.rb -u <username> -k <apikey> [-f <filename>]
#
# == Options
#
# --help, -h                   show help
# --apikey, -k <api_key>       last.fm api key
# --username, -u <username>    last.fm username
# --datafile, -f <filename>    datafile name (optional)
#


require 'active_support/inflector' rescue "This script depends on the active_support gem. Please run '(sudo) gem install activesupport'."
require 'appscript'                rescue "This script depends on the rb-appscript gem. Please run '(sudo) gem install rb-appscript'."
require 'getoptlong'
require 'nokogiri'                 rescue "This script depends on the Nokogiri gem. Please run '(sudo) gem install nokogiri'."
require 'open-uri'
require 'progress_bar'             rescue "This script depends on the progress_bar gem. Please run '(sudo) gem install progress_bar'."
require 'unidecoder'               rescue "This script depends on the unidecoder gem. Please run '(sudo) gem install unidecoder'."

I18n.enforce_available_locales = false

$api_version = '2.0'
$api_baseurl = "http://ws.audioscrobbler.com/%s/" % [$api_version]
$api_limit = 100
$data_file = 'lastfm2itunes.dat'


def usage()
  puts ""
  puts "Last.fm to iTunes script"
  puts "Usage:"
  puts "  ruby lastfm2itunes.rb -u <username> -k <apikey> [-f <filename>]"
  puts "Options:"
  puts "  -h, --help       show help"
  puts "  -k, --apikey     last.fm api key"
  puts "  -u, --username   last.fm username"
  puts "  -f, --datafile   datafile name (optional)"
  puts ""
end


def get_lastfm_playcounts(username, apikey)
  puts "Fetching data from last.fm..."
  playcounts = {}
  xmldoc = Nokogiri::XML(open("#{$api_baseurl}?method=user.getTopTracks&user=#{username}&api_key=#{apikey}&limit=#{$api_limit}&page=1"), nil, 'UTF-8')
  total_pages = xmldoc.xpath('/lfm/toptracks/@totalPages').text.to_i
  bar = ProgressBar.new(total_pages, :bar, :counter)
  for page in (1..total_pages)
    xmldoc = Nokogiri::XML(open("#{$api_baseurl}?method=user.getTopTracks&user=#{username}&api_key=#{apikey}&limit=#{$api_limit}&page=#{page}"), nil, 'UTF-8')
    tracks = xmldoc.xpath('/lfm/toptracks/track')
    tracks.each do |track|
      playcount = track.xpath('playcount').text.to_i
      artist = track.xpath('artist/name').text.to_ascii.parameterize
      name = track.xpath('name').text.to_ascii.parameterize
      ## puts "#{playcount} : #{artist} - #{name}"
      playcounts[artist] ||= {}
      playcounts[artist][name] ||= 0
      playcounts[artist][name] += playcount
    end
    sleep 0.2
    bar.increment!
  end
  return playcounts
end


def load_data(datafile)
  data = nil
  if File.file?(datafile)
    puts "Loading file..."
    in_file = File.binread(datafile)
    data = Marshal.load(in_file)
  else
    puts "Data file not found."
  end
  return data
end


def save_data(datafile, data)
  puts "Writing to file..."
  File.open(datafile, 'wb') do |out_file|
    out_file.write(Marshal.dump(data))
  end
end


def update_itunes(playcounts)
  puts "Updating iTunes..."
  results = {'artists' => {'miss' => {}}, 'tracks' => {'miss' => {}, 'updated' => {}, 'not_updated' => {}}}
  itunes = Appscript.app('iTunes')
  tracks = itunes.tracks.get
  bar = ProgressBar.new(tracks.length, :bar, :counter)
  tracks.each do |track|
    track_playcount = track.played_count.get.to_i
    track_artist = track.artist.get.to_ascii.parameterize
    track_name = track.name.get.to_ascii.parameterize
    ## puts "#{track_playcount} : #{track_artist} - #{track_name}"
    lastfm_artist = playcounts[track_artist]
    if lastfm_artist.nil?
      # artist not yet in last.fm
      results['artists']['miss'][track_artist] ||= 0
      results['artists']['miss'][track_artist] += 1
      bar.increment!
      next
    end
    lastfm_playcount = lastfm_artist[track_name]
    if lastfm_playcount.nil?
      # track not yet in last.fm
      results['tracks']['miss'][track_artist] ||= {}
      results['tracks']['miss'][track_artist][track_name] ||= 0
      results['tracks']['miss'][track_artist][track_name] += 1
      bar.increment!
      next
    end
    if lastfm_playcount > track_playcount
      # count updated
      results['tracks']['updated'][track_artist] ||= {}
      results['tracks']['updated'][track_artist][track_name] ||= {'from' => track_playcount, 'to' => lastfm_playcount}
      track.played_count.set(lastfm_playcount)
    else
      # count not updated
      results['tracks']['not_updated'][track_artist] ||= {}
      results['tracks']['not_updated'][track_artist][track_name] ||= {'from' => track_playcount, 'to' => lastfm_playcount}
    end
    bar.increment!
  end
  ## puts results
  artists_miss = results['artists']['miss'].values.reduce(:+) || 0
  tracks_miss = results['tracks']['miss'].values.map{ |b| b.values.reduce(:+) }.reduce(:+) || 0
  tracks_updated = results['tracks']['updated'].values.map { |b| b.values.length }.reduce(:+) || 0
  tracks_not_updated = results['tracks']['not_updated'].values.map { |b| b.values.length }.reduce(:+) || 0
  puts "%i band misses" % artists_miss
  puts "%i song misses" % tracks_miss
  puts "%i songs updated" % tracks_updated
  puts "%i songs not updated" % tracks_not_updated
end


def main()
  apikey = nil
  username = nil
  datafile = $data_file
  opts = GetoptLong.new(
    [ '--help', '-h', GetoptLong::NO_ARGUMENT ],
    [ '--apikey', '-k', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--username', '-u', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--datafile', '-f', GetoptLong::REQUIRED_ARGUMENT ]
  )
  begin
    opts.each do |opt, arg|
      case opt
      when "--help"
        usage()
        exit 2
      when "--apikey"
        apikey = arg
      when "--username"
        username = arg
      when "--datafile"
        datafile = arg
      end
    end
  rescue StandardError=>my_error_message
    usage()
    exit 3
  end
  if username.nil? or apikey.nil?
    usage()
    exit 4
  end
  playcounts = load_data(datafile)
  if playcounts.nil?
    playcounts = get_lastfm_playcounts(username, apikey)
    save_data(datafile, playcounts)
  end
  update_itunes(playcounts)
end


if __FILE__==$0
  begin
    main
  rescue Interrupt => e
    nil
  end
end
