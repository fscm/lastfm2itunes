# lastfm2itunes

Update your iTunes "played counts" with your Last.fm scrobbles.

## Synopsis

This script will try to update the "played count" and the "played date" value
of your iTunes songs by getting the number of scrobbles for those songs from
a [http://last.fm/](last.fm) profile.

Differences in song titles and the usage of special characters on song names
may prevent the script from recognizing the songs properly.

The script is available on both Ruby and Python. Both versions will perform the
same tasks however, due to the way that both languages deal with character
encoding, normalization and parameterization, the results may be different.
Please use the one that produces the best results for your iTunes library.

## Getting Started

There are a couple of things needed for either of the scripts to work.

### Prerequisites

Follow the instructions for the version of the script that you wish to use.
Last.fm instructions are required for both versions.

#### Last.fm

A last.fm user account is required (to obtain the scrobbles from). You can
create an account at [http://last.fm/join](http://www.last.fm/join) if you do
not have one already.

A last.fm API account is also required. You can obtain an API key at
[http://last.fm/api](http://www.last.fm/api/account/create)


#### Ruby

For the Ruby version of the script the following gems are required:

* getoptlong
* json
* open-uri
* progress_bar
* rb-appscript
* unidecoder

You can install gems with:

```
sudo gem install <gem_name>
```

#### Python

For the Python version of the script the following modules are required:

* appscript
* getopt
* json
* os.path
* progress
* requests
* sys
* time
* unidecode

You can install modules with:

```
sudo pip install <module_name>
```

### Installation

Nothing special to be done. Just download the version of the script that you
wish to use.

### Usage

Both versions of the script use the same arguments.

#### Ruby

```
Usage:
  lastfm2itunes.rb -u <username> -k <apikey> [-f <filename>] [-h] [-p]
Options:
  -f, --datafile <filename>  datafile name (optional)
  -h, --help                 show help (optional)
  -k, --apikey <api_key>     last.fm api key
  -p, --lastplayed           update the last played date (optional)
  -u, --username <username>  last.fm username
```

#### Python

```
Usage:
  lastfm2itunes.py -u <username> -k <apikey> [-f <filename>] [-h] [-p]
Options:
  -f, --datafile <filename>  datafile name (optional)
  -h, --help                 show help (optional)
  -k, --apikey <api_key>     last.fm api key
  -p, --lastplayed           update the last played date (optional)
  -u, --username <username>  last.fm username
```

## Contributing

1. Fork it!
2. Create your feature branch: `git checkout -b my-new-feature`
3. Commit your changes: `git commit -am 'Add some feature'`
4. Push to the branch: `git push origin my-new-feature`
5. Submit a pull request

## Versioning

This project uses [SemVer](http://semver.org/) for versioning. For the versions
available, see the [tags on this repository](https://github.com/fscm/lastfm2itunes/tags).

## Authors

* **Frederico Martins** - [fscm](https://github.com/fscm)

See also the list of [contributors](https://github.com/fscm/lastfm2itunes/contributors)
who participated in this project.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE)
file for details
