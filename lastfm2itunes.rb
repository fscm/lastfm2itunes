#!/usr/bin/ruby
#
# -*- encoding: utf-8 -*-
# coding: UTF-8
# encoding: utf-8
#
# copyright: 2016-2019, Frederico Martins
# author: Frederico Martins <http://github.com/fscm>
# license: SPDX-License-Identifier: MIT
#
#
# == Synopsis
#
# lastfm2itunes: Update iTunes playcounts from last.fm
#
# == Requires
#
# - getoptlong
# - json
# - net/http
# - progress_bar
# - rb-appscript
# - time
# - uri
# - unidecoder
#
# == Usage
#
# lastfm2itunes.rb -u <username> -k <apikey> [-f <filename>] [-h] [-p]
#
# == Options
#
# -f, --datafile <filename>  datafile name (optional)
# -h, --help                 show help (optional)
# -k, --apikey <api_key>     last.fm api key
# -p, --lastplayed           update the last played date (optional)
# -u, --username <username>  last.fm username
#


require 'appscript'
require 'getoptlong'
require 'json'
require 'net/http'
require 'progress_bar'
require 'time'
require 'uri'
require 'unidecoder'

I18n.enforce_available_locales = false


$API_VERSION = "2.0"
$API_BASEURL = "http://ws.audioscrobbler.com/%s/" % [$API_VERSION]
$API_FORMAT = 'json'
$API_LIMIT = 100
$DATA_FILE = 'lastfm2itunes.json'
$DATE_NOW = Time.now.utc.to_i


def usage()
  puts ""
  puts "Last.fm to iTunes script"
  puts "Usage:"
  puts "  %{lastfm2itunes} -u <username> -k <apikey> [-f <filename>] [-h] [-p]" % {:lastfm2itunes => File.basename($0)}
  puts "Options:"
  puts "  -f, --datafile <filename>  datafile name (optional)"
  puts "  -h, --help                 show help (optional)"
  puts "  -k, --apikey <api_key>     last.fm api key"
  puts "  -p, --lastplayed           update the last played date (optional)"
  puts "  -u, --username <username>  last.fm username"
  puts ""
end


def load_data(datafile)
  data = nil
  if File.file?(datafile)
    puts "Loading file..."
    in_file = File.read(datafile)
    begin
      data = JSON.parse(in_file)
    rescue JSON::ParserError
      puts "Invalid data file"
    end
  else
    puts "Data file not found."
  end
  return data
end


def save_data(datafile, data)
  puts "Writing to file..."
  File.open(datafile, 'w') do |out_file|
    out_file.write(JSON.dump(data))
  end
end


def get_lastfm_playcounts(username, apikey, playcounts={}, last_updated=0)
  puts "Fetching data from last.fm..."
  from_ts = last_updated.to_i
  to_ts = $DATE_NOW
  payload = {
    'method' => 'user.getRecentTracks',
    'user' => username,
    'api_key' => apikey,
    'from' => from_ts,
    'to' => to_ts,
    'format' => $API_FORMAT,
    'limit' => $API_LIMIT,
    'page' => 1 }
  uri = URI.parse($API_BASEURL)
  http = Net::HTTP.new(uri.host, uri.port)
  post = Net::HTTP::Post.new(uri.path)
  post.set_form_data(payload)
  jsondoc = JSON.parse(http.request(post).body)
  total_pages = jsondoc['recenttracks']['@attr']['totalPages'].to_i
  if total_pages < 1
    return {'last_updated' => to_ts, 'playcounts' => playcounts}
  end
  bar = ProgressBar.new(total_pages, :bar, :counter)
  for page in (1..total_pages)
    payload = {
      'method' => 'user.getRecentTracks',
      'user' => username,
      'api_key' => apikey,
      'from' => from_ts,
      'to' => to_ts,
      'format' => $API_FORMAT,
      'limit' => $API_LIMIT,
      'page' => page }
    post.set_form_data(payload)
    jsondoc = JSON.parse(http.request(post).body)
    tracks = jsondoc['recenttracks']['track']
    tracks.each do |track|
      track_artist = track['artist']['#text'].to_ascii.downcase
      track_album = track['album']['#text'].to_ascii.downcase
      track_name = track['name'].to_ascii.downcase
      track_last_played = track['date']['uts'].to_i
      #puts "#{track_last_played}: #{track_artist} - #{track_album} - #{track_name}"
      playcounts[track_artist] ||= {}
      playcounts[track_artist][track_album] ||= {}
      playcounts[track_artist][track_album][track_name] ||= {}
      playcounts[track_artist][track_album][track_name]['play_count'] = \
        playcounts[track_artist][track_album][track_name].fetch('play_count', 0) + 1
      if playcounts[track_artist][track_album][track_name]['last_played'].nil?
        playcounts[track_artist][track_album][track_name]['last_played'] = track_last_played
      end
    end
    sleep 0.2
    bar.increment!
  end
  return {'last_updated' => to_ts, 'playcounts' => playcounts}
end


def update_itunes(playcounts, lastplayed=False)
  puts "Updating iTunes..."
  results = {
    'artists' => {'miss' => {}},
    'albums' => {'miss' => {}},
    'tracks' => {
      'miss' => {},
      'updated' => {},
      'not_updated' => {},
      'lastplayed_updated' => {},
      'lastplayed_not_updated' => {} } }
  itunes = Appscript.app('iTunes')
  library = itunes.library_playlists['Library']
  tracks = library.tracks.get
  bar = ProgressBar.new(tracks.length, :bar, :counter)
  tracks.each do |track|
    track_playcount = track.played_count.get.to_i
    track_artist = track.artist.get.to_ascii.downcase
    track_album = track.album.get.to_ascii.downcase
    track_name = track.name.get.to_ascii.downcase
    begin
      track_last_played = track.played_date.get.to_i
    rescue
      track_last_played = 0
    end
    lastfm_artist = playcounts[track_artist]
    if lastfm_artist.nil?
      # artist not yet in last.fm
      results['artists']['miss'][track_artist] ||= 0
      results['artists']['miss'][track_artist] += 1
      bar.increment!
      next
    end
    lastfm_album = lastfm_artist[track_album]
    if lastfm_album.nil?
      # album not yet in last.fm
      results['albums']['miss'][track_album] ||= 0
      results['albums']['miss'][track_album] += 1
      bar.increment!
      next
    end
    lastfm_track = lastfm_album[track_name]
    if lastfm_track.nil?
      # track not yet in last.fm
      results['tracks']['miss'][track_artist] ||= {}
      results['tracks']['miss'][track_artist][track_name] ||= 0
      results['tracks']['miss'][track_artist][track_name] += 1
      bar.increment!
      next
    end
    lastfm_playcount = lastfm_track['play_count'].to_i
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
    lastfm_lastplayed = lastfm_track['last_played'].to_i
    if lastplayed
      if lastfm_lastplayed > track_last_played
        # count updated
        results['tracks']['lastplayed_updated'][track_artist] ||= {}
        results['tracks']['lastplayed_updated'][track_artist][track_name] ||= {'from' => track_last_played, 'to' => lastfm_lastplayed}
        track.played_date.set(Time.at(lastfm_lastplayed))
      else
        # count not updated
        results['tracks']['lastplayed_not_updated'][track_artist] ||= {}
        results['tracks']['lastplayed_not_updated'][track_artist][track_name] ||= {'from' => track_last_played, 'to' => lastfm_lastplayed}
      end
    end
    #puts "#{track_last_played}: #{track_artist} - #{track_album} - #{track_name} (#{track_playcount}->#{lastfm_playcount})"
    bar.increment!
  end
  #puts results
  artists_miss = results['artists']['miss'].values.reduce(:+) || 0
  albums_miss = results['albums']['miss'].values.reduce(:+) || 0
  tracks_miss = results['tracks']['miss'].values.map{ |b| b.values.reduce(:+) }.reduce(:+) || 0
  tracks_updated = results['tracks']['updated'].values.map { |b| b.values.length }.reduce(:+) || 0
  tracks_not_updated = results['tracks']['not_updated'].values.map { |b| b.values.length }.reduce(:+) || 0
  tracks_lastplayed_updated = results['tracks']['lastplayed_updated'].values.map { |b| b.values.length }.reduce(:+) || 0
  tracks_lastplayed_not_updated = results['tracks']['lastplayed_not_updated'].values.map { |b| b.values.length }.reduce(:+) || 0
  puts "#{artists_miss} band misses"
  puts "#{albums_miss} album misses"
  puts "#{tracks_miss} song misses"
  puts "#{tracks_updated}/#{tracks_lastplayed_updated} songs updated"
  puts "#{tracks_not_updated}/#{tracks_lastplayed_not_updated} songs not updated"
end


def main()
  apikey = nil
  username = nil
  datafile = $DATA_FILE
  last_updated = 0
  playcounts = {}
  lastplayed = false
  if ARGV.length < 1
    usage()
    exit 0
  end
  opts = GetoptLong.new(
    [ '--help', '-h', GetoptLong::NO_ARGUMENT ],
    [ '--apikey', '-k', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--username', '-u', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--datafile', '-f', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--lastplayed', '-p', GetoptLong::NO_ARGUMENT ]
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
      when "--lastplayed"
        lastplayed = true
      end
    end
  rescue StandardError => my_error_message
    exit 3
  end
  if username.nil? or apikey.nil?
    STDERR.puts "  'username' and 'apikey' are mandatory"
    exit 4
  end
  data = load_data(datafile)
  if data
    last_updated = data.fetch('last_updated', 0).to_i
    playcounts = data.fetch('playcounts', {})
  end
  data = get_lastfm_playcounts(username, apikey, playcounts, last_updated)
  save_data(datafile, data)
  update_itunes(data['playcounts'], lastplayed)
end


if __FILE__==$0
  begin
    main
  rescue Interrupt => e
    nil
  end
end
