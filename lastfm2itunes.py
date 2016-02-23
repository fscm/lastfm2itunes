#!/usr/bin/python

'''\nLast.fm to iTunes script
Usage: 
  lastfm2itunes.py -u <username> -k <apikey> [-f <filename>]
Options:
  --help, -h                   show help
  --apikey, -k <api_key>       last.fm api key
  --username, -u <username>    last.fm username
  --datafile, -f <filename>    datafile name (optional)
'''


import inflection
import getopt
import marshal
import os.path
import requests
import sys

from appscript import *
from progress.bar import Bar
from time import sleep
from xml.dom import minidom


api_version = "2.0"
api_baseurl = "http://ws.audioscrobbler.com/%s/" % api_version
data_file = 'lastfm2itunes.dat'


def usage():
    print sys.exit(__doc__)


def get_lastfm_playcounts(username, apikey):
    print "Fetching data from last.fm..."
    playcounts = {}
    payload = {'method':'user.getTopTracks', 'user':username, 'api_key':apikey}
    r = requests.post(api_baseurl, data = payload)
    xmldoc = minidom.parseString(r.text.encode('utf-8'))
    total_pages = int(xmldoc.getElementsByTagName('toptracks')[0].attributes['totalPages'].value)
    bar = Bar('Fetching', max=total_pages)
    for page in range(total_pages):
        payload = {'method':'user.getTopTracks', 'user':username, 'api_key':apikey, 'page':page}
        r = requests.post(api_baseurl, data = payload)
        xmldoc = minidom.parseString(r.text.encode('utf-8'))
        tracks = xmldoc.getElementsByTagName('track')
        for track in tracks:
            track_playcount = int(track.getElementsByTagName('playcount')[0].childNodes[0].data)
            track_artist = str(inflection.parameterize(track.getElementsByTagName('artist')[0].getElementsByTagName('name')[0].childNodes[0].data.lower()))
            track_name = str(inflection.parameterize(track.getElementsByTagName('name')[0].childNodes[0].data.lower()))
            playcounts.setdefault(track_artist, {})
            playcounts[track_artist].setdefault(track_name, 0)
            playcounts[track_artist][track_name] = track_playcount
            ## print "%i : %s - %s" % (track_playcount, track_artist, track_title)
        sleep(0.2)
        bar.next()
    bar.finish()
    return playcounts


def load_data(datafile):
    data = None
    if os.path.isfile(datafile):
        print "Loading file..."
        in_file = open(datafile, 'rb')
        data = marshal.load(in_file)
        in_file.close()
    else:
        print "Data file not found."
    return data


def save_data(datafile, data):
    print "Writing to file..."
    out_file = open(datafile, 'wb')
    marshal.dump(data, out_file)
    out_file.close()


def update_itunes(playcounts):
    print "Updating iTunes..."
    results = {'artists':{'miss':{}}, 'tracks':{'miss':{}, 'updated':{}, 'not_updated':{}}}
    itunes = app('iTunes')
    library = itunes.library_playlists['Library']
    tracks = library.file_tracks()
    bar = Bar('Updating', max=len(tracks))
    for track in tracks:
        track_playcount = int(track.played_count())
        track_artist = str(inflection.parameterize(track.artist().lower()))
        track_name = str(inflection.parameterize(track.name().lower()))
        ## print "%i : %s - %s" % (track_playcount, track_artist, track_name)
        lastfm_artist = playcounts.get(track_artist, None)
        if lastfm_artist is None:
            # artist not yet in last.fm
            results['artists']['miss'].setdefault(track_artist, 0)
            results['artists']['miss'][track_artist] += 1
            bar.next()
            continue
        lastfm_playcount = lastfm_artist.get(track_name, None)
        if lastfm_playcount is None:
            # track not yet in last.fm
            results['tracks']['miss'].setdefault(track_artist, {})
            results['tracks']['miss'][track_artist].setdefault(track_name, 0)
            results['tracks']['miss'][track_artist][track_name] += 1
            bar.next()
            continue
        if lastfm_playcount > track_playcount:
            # count updated
            results['tracks']['updated'].setdefault(track_artist, {})
            results['tracks']['updated'][track_artist].setdefault(track_name, {'from':track_playcount, 'to':lastfm_playcount})
            track.played_count.set(lastfm_playcount)
        else:
            # count not updated
            results['tracks']['not_updated'].setdefault(track_artist, {})
            results['tracks']['not_updated'][track_artist].setdefault(track_name, {'from':track_playcount, 'to':lastfm_playcount})
        bar.next()
    bar.finish()
    ## print results
    artists_miss = reduce(lambda x,y: x+y, results['artists']['miss'].values())
    tracks_miss = reduce(lambda x,y: x+y, map(lambda x: reduce(lambda x,y: x+y, x.values()), results['tracks']['miss'].values()))
    tracks_updated = reduce(lambda x,y: x+y, map(lambda x: len(x.keys()), results['tracks']['updated'].values()))
    tracks_not_updated = reduce(lambda x,y: x+y, map(lambda x: len(x.keys()), results['tracks']['not_updated'].values()))
    print "%i band misses" % artists_miss
    print "%i song misses" % tracks_miss
    print "%i songs updated" % tracks_updated
    print "%i songs not updated" % tracks_not_updated


def main(argv):
    username = None
    apikey = None
    datafile = data_file
    try:
        opts, args = getopt.getopt(argv, "hu:k:f:", ["help", "username=", "apikey=", "file="])
    except getopt.GetoptError as err:
        print str(err)
        usage()
        sys.exit(2)
    for opt, arg in opts:
        if opt in ('-h', '--help'):
            usage()
            sys.exit()
        elif opt in ('-u', '--username'):
            username = arg
        elif opt in ('-k', '--apikey'):
            apikey = arg
        elif opt in ('-f', '--file'):
            datafile = arg
    if username is None or apikey is None:
        print str("'username' and apikey are mandatory")
        usage()
        sys.exit(3)
    playcounts = load_data(datafile)
    if playcounts is None:
        playcounts = get_lastfm_playcounts(username, apikey)
        save_data(datafile, playcounts)
    update_itunes(playcounts)


if __name__ == "__main__":
    main(sys.argv[1:])

