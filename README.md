# GeneValidatorApp
[![Build Status](https://travis-ci.org/IsmailM/GeneValidatorApp.svg?branch=master)](https://travis-ci.org/IsmailM/GeneValidatorApp)
[![Gem Version](https://badge.fury.io/rb/GeneValidatorApp.svg)](http://badge.fury.io/rb/GeneValidatorApp)
[![Dependency Status](https://gemnasium.com/IsmailM/GeneValidatorApp.svg)](https://gemnasium.com/IsmailM/GeneValidatorApp)
[![Scrutinizer Code Quality](https://scrutinizer-ci.com/g/IsmailM/GeneValidatorApp/badges/quality-score.png?b=master)](https://scrutinizer-ci.com/g/IsmailM/GeneValidatorApp/?branch=master)

This is a Sinatra based web wrapper for [GeneValidator](https://github.com/monicadragan/GeneValidator); a program that validates gene predictions. A working example can be seen at [genevalidator.sbcs.qmul.ac.uk](http://genevalidator.sbcs.qmul.ac.uk).

If you use this program in your research, please cite us as follows:

"Dragan M, Moghul MI, Priyam A & Wurm Y (<em>in prep</em>) GeneValidator: identify problematic gene predictions" 

This program was developed at [Wurm Lab](http://yannick.poulet.org), [QMUL](http://sbcs.qmul.ac.uk) with the support of a BBSRC grant.

## Installation

1) Install all GeneValidator Prerequisites (ruby <=1.9.3, Mafft, BLAST+). You would also require a BLAST database. 
  * Please see [here](https://gist.github.com/IsmailM/b783e8a06565197084e6) for more information.

2) Install GeneValidatorApp

    $ gem install GeneValidatorApp

## Usage

After installing simply type in:

    $ genevalidatorapp

and then go to [http://localhost:4567](http://localhost:4567) (if on a local server and using the default port: 4567)

See `$ genevalidator -h` for more information on how to run GeneValidatorApp.

    USAGE
    
    genevalidatorapp [options]
    
    Example
    
      # Launch GeneValidatorApp with the given config file
      $ genevalidatorapp --config ~/.genevalidatorapp.conf
    
      # Launch GeneValidatorApp with 8 threads at port 8888
      $ genevalidatorapp --num_threads 8 --port 8888

      # Create a config file with the other arguments
      $ genevalidatorapp -s -d ~/database_dir 
    
    Compulsory (unless set in a config file)
        -d, --database_dir          Read BLAST database from this directory
        
    Optional
        -f, --default_db            The Path to the the default database
        -n, --num_threads           Number of threads to use to run a BLAST search
        -c, --config_file           Use the given configuration file
        -r, --require               Load extension from this file
        -p, --port                  Port to run GeneValidatorApp on
        -s, --set                   Set configuration value in default or given config file
        -l, --list_databases        List BLAST databases
        -b, --blast_bin             Load BLAST+ binaries from this directory
        -m, --mafft_bin             Load Mafft binaries from this directory
        -D, --devel                 Start GeneValidatorApp in development mode
        -v, --version               Print version number of GeneValidatorApp that will be loaded
        -h, --help                  Display this help message.


## Setting up a Config File

GeneValidatorApp requires a number of arguments in order to work. You can either provide these variables to the app through a config file or through command line arguments.

In order to create a config file, run genevalidator with the `-s` or `--set` argument as follows.

    $ genevalidator -s -d database_dir -f default_db -n num_threads -p port -b blast_bin -m mafft_bin

The `--set` argument create a config file at `~/.genevalidatorapp.conf` using all the other arguments used. Thereafter, GeneValidatorApp will read the config file before starting the app. This means that you are not required provide the same arguments again and again.

### Config file

A config file can also be set up manually. Below is an example:   

    :database_dir: "/Users/ismailm/blastdb"
    :default_db: "/Users/ismailm/blastdb/SwissProt"
    :web_dir: "/Users/ismailm/GV"
    :num_threads: 8
    :port: 4567
    :host: localhost
    :devel: true
    :blast_bin: "/Users/ismailm/blast/bin"
    :mafft_bin: "/Users/ismailm/mafft/bin"

## API

See [GeneValidatorApp-API](https://github.com/IsmailM/GeneValidatorApp-API) for more information.

## Contributing

1. Fork it ( https://github.com/IsmailM/GeneValidatorApp/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
