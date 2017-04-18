#!/usr/bin/python
# -*- coding: UTF-8 -*-

'''
Last.fm to iTunes script
Usage:
  {lastfm2itunes} -u <username> -k <apikey> [-f <filename>] [-h] [-p]
Options:
  -f, --datafile <filename>  datafile name (optional)
  -h, --help                 show help (optional)
  -k, --apikey <api_key>     last.fm api key
  -p, --lastplayed           update the last played date (optional)
  -u, --username <username>  last.fm username
'''


import getopt
import json
import os.path
import requests
import sys

from appscript import *
from datetime import datetime
from progress.bar import Bar
from time import altzone, daylight, sleep, timezone
from unidecode import unidecode


API_VERSION = "2.0"
API_BASEURL = "http://ws.audioscrobbler.com/%s/" % API_VERSION
API_FORMAT = 'json'
API_LIMIT = 100
DATA_FILE = 'lastfm2itunes.json'
DATE_EPOCH = datetime.utcfromtimestamp(0)
DATE_NOW = datetime.utcnow().replace(microsecond=0)


def usage():
    print(sys.exit(__doc__.format(lastfm2itunes = sys.argv[0].split('/')[-1])))


def load_data(datafile):
    data = None
    if os.path.isfile(datafile):
        print("Loading file...")
        in_file = open(datafile, 'r')
        try:
            data = json.load(in_file)
        except ValueError as err:
            print("Invalid data file")
        in_file.close()
    else:
        print("Data file not found.")
    return data


def save_data(datafile, data):
    print("Writing to file...")
    out_file = open(datafile, 'w')
    try:
        json.dump(data, out_file, skipkeys=True)
    except:
        print("Unable to write to file")
    out_file.close()


def get_lastfm_playcounts(username, apikey, playcounts={}, last_updated=0):
    print("Fetching data from last.fm...")
    from_ts = int(last_updated)
    to_ts = int((DATE_NOW - DATE_EPOCH).total_seconds())
    payload = {
        'method':'user.getRecentTracks',
        'user':username,
        'api_key':apikey,
        'from':from_ts,
        'to':to_ts,
        'format':API_FORMAT,
        'limit':API_LIMIT,
        'page':1 }
    session = requests.session()
    r = session.post(API_BASEURL, data=payload)
    jsondoc = json.loads(r.text.encode('utf-8'))
    total_pages = int(jsondoc['recenttracks']['@attr']['totalPages'])
    bar = Bar('Fetching', max=total_pages)
    for page in range(1, total_pages+1):
        payload = {
            'method':'user.getRecentTracks',
            'user':username,
            'api_key':apikey,
            'from':from_ts,
            'to':to_ts,
            'format':API_FORMAT,
            'limit':API_LIMIT,
            'page':page }
        r = session.post(API_BASEURL, data = payload)
        jsondoc = json.loads(r.text.encode('utf-8'))
        tracks = jsondoc['recenttracks']['track']
        for track in tracks:
            track_artist = unidecode(track['artist']['#text']).encode('ascii').lower()
            track_album = unidecode(track['album']['#text']).encode('ascii').lower()
            track_name = unidecode(track['name']).encode('ascii').lower()
            track_last_played = int(track['date']['uts'])
            #print("{0}: {1} - {2} - {3}".format(
            #    track_last_played,
            #    track_artist,
            #    track_album,
            #    track_name ) )
            playcounts.setdefault(track_artist, {})
            playcounts[track_artist].setdefault(track_album, {})
            playcounts[track_artist][track_album].setdefault(track_name, {})
            playcounts[track_artist][track_album][track_name]['play_count'] = \
                playcounts[track_artist][track_album][track_name].get('play_count', 0) + 1
            if not playcounts[track_artist][track_album][track_name].get('last_played'):
                playcounts[track_artist][track_album][track_name]['last_played'] = track_last_played
        sleep(0.2)
        bar.next()
    bar.finish()
    return {'last_updated':to_ts, 'playcounts':playcounts}


def update_itunes(playcounts, lastplayed=False):
    print "Updating iTunes..."
    results = {
        'artists':{'miss':{}},
        'albums':{'miss':{}},
        'tracks':{
            'miss':{},
            'updated':{},
            'not_updated':{},
            'lastplayed_updated':{},
            'lastplayed_not_updated':{} } }
    itunes = app('iTunes')
    library = itunes.library_playlists['Library']
    tracks = library.tracks()
    bar = Bar('Updating', max=len(tracks))
    for track in tracks:
        track_playcount = int(track.played_count())
        track_artist = unidecode(track.artist()).encode('ascii').lower()
        track_album = unidecode(track.album()).encode('ascii').lower()
        track_name = unidecode(track.name()).encode('ascii').lower()
        try:
            track_lastplayed = int((track.played_date() - DATE_EPOCH).total_seconds() + (altzone if daylight else timezone))
        except:
            track_lastplayed = 0
        lastfm_artist = playcounts.get(track_artist, None)
        if not lastfm_artist:
            # artist not yet in last.fm
            results['artists']['miss'].setdefault(track_artist, 0)
            results['artists']['miss'][track_artist] += 1
            bar.next()
            continue
        lastfm_album = lastfm_artist.get(track_album, None)
        if not lastfm_album:
            # album not yet in last.fm
            results['albums']['miss'].setdefault(track_album, 0)
            results['albums']['miss'][track_album] += 1
            bar.next()
            continue
        lastfm_track = lastfm_album.get(track_name, None)
        if not lastfm_track:
            # track not yet in last.fm
            results['tracks']['miss'].setdefault(track_artist, {})
            results['tracks']['miss'][track_artist].setdefault(track_name, 0)
            results['tracks']['miss'][track_artist][track_name] += 1
            bar.next()
            continue
        lastfm_playcount = int(lastfm_track['play_count'])
        if lastfm_playcount > track_playcount:
            # count updated
            results['tracks']['updated'].setdefault(track_artist, {})
            results['tracks']['updated'][track_artist].setdefault(
                track_name, {'from':track_playcount, 'to':lastfm_playcount} )
            track.played_count.set(lastfm_playcount)
        else:
            # count not updated
            results['tracks']['not_updated'].setdefault(track_artist, {})
            results['tracks']['not_updated'][track_artist].setdefault(
                track_name, {'from':track_playcount, 'to':lastfm_playcount} )
        lastfm_lastplayed = int(lastfm_track['last_played'])
        if lastplayed:
            if lastfm_lastplayed > track_lastplayed:
                # count updated
                results['tracks']['lastplayed_updated'].setdefault(track_artist, {})
                results['tracks']['lastplayed_updated'][track_artist].setdefault(
                    track_name, {'from':track_lastplayed, 'to':lastfm_lastplayed} )
                track.played_date.set(datetime.fromtimestamp(lastfm_lastplayed - (altzone if daylight else timezone)))
            else:
                # count not updated
                results['tracks']['lastplayed_not_updated'].setdefault(track_artist, {})
                results['tracks']['lastplayed_not_updated'][track_artist].setdefault(
                    track_name, {'from':track_lastplayed, 'to':lastfm_lastplayed} )
        #print("{0}: {1} - {2} - {3} ({4}->{5})".format(
        #    track_last_played,
        #    track_artist.encode('utf-8'),
        #    track_album.encode('utf-8'),
        #    track_name.encode('utf-8'),
        #    track_playcount,
        #    lastfm_playcount ) )
        bar.next()
    bar.finish()
    #print(results)
    print results['tracks']['lastplayed_updated']
    artists_miss = reduce(lambda x,y: x+y, results['artists']['miss'].values() or [0])
    albums_miss = reduce(lambda x,y: x+y, results['albums']['miss'].values() or [0])
    tracks_miss = reduce(lambda x,y: x+y, map(lambda x: reduce(lambda x,y: x+y, x.values()), results['tracks']['miss'].values()) or [0])
    tracks_updated = reduce(lambda x,y: x+y, map(lambda x: len(x.keys()), results['tracks']['updated'].values()) or [0])
    tracks_not_updated = reduce(lambda x,y: x+y, map(lambda x: len(x.keys()), results['tracks']['not_updated'].values()) or [0])
    tracks_lastplayed_updated = reduce(lambda x,y: x+y, map(lambda x: len(x.keys()), results['tracks']['lastplayed_updated'].values()) or [0])
    tracks_lastplayed_not_updated = reduce(lambda x,y: x+y, map(lambda x: len(x.keys()), results['tracks']['lastplayed_not_updated'].values()) or [0])
    print("{} band misses".format(artists_miss))
    print("{} album misses".format(albums_miss))
    print("{} song misses".format(tracks_miss))
    print("{}/{} songs updated".format(tracks_updated, tracks_lastplayed_updated))
    print("{}/{} songs not updated".format(tracks_not_updated, tracks_lastplayed_not_updated))


def main(argv):
    username = None
    apikey = None
    datafile = DATA_FILE
    last_updated = 0
    playcounts = {}
    lastplayed = False
    try:
        opts, args = getopt.getopt(argv, "hu:k:f:p", ["help", "username=", "apikey=", "file=", "lastplayed"])
    except getopt.GetoptError as err:
        sys.exit("  " + str(err))
    if not opts:
        usage()
    for opt, arg in opts:
        if opt in ('-h', '--help'):
            usage()
        elif opt in ('-u', '--username'):
            username = arg
        elif opt in ('-k', '--apikey'):
            apikey = arg
        elif opt in ('-f', '--file'):
            datafile = arg
        elif opt in ('-p', '--lastplayed'):
            lastplayed = True
    if not username or not apikey:
        sys.exit(str("  'username' and 'apikey' are mandatory"))
    data = load_data(datafile)
    if data:
        last_updated = data.get('last_updated', 0)
        playcounts = data.get('playcounts', {})
    playcounts = get_lastfm_playcounts(username, apikey, playcounts, last_updated)
    save_data(datafile, playcounts)
    update_itunes(playcounts['playcounts'], lastplayed)


if __name__ == "__main__":
    main(sys.argv[1:])
