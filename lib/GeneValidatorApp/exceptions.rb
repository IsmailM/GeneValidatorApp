#!/usr/bin/env ruby
require 'slop'

ENV['RACK_ENV'] ||= 'production'

# display name for tools like `ps`
$PROGRAM_NAME = 'genevalidatorapp'

opts = Slop.parse do |o|
  o.banner = <<BNR

SUMMARY:
  GeneValidator - Identify problems with predicted genes

USAGE:
  $ genevalidatorapp [options]

Examples:
  # Launch GeneValidatorApp with the given config file
  $ genevalidatorapp --config ~/.genevalidatorapp.conf

  # Launch GeneValidatorApp with 8 threads at port 8888
  $ genevalidatorapp --num_threads 8 --port 8888

  # Create a config file with the other arguments
  $ genevalidatorapp -s -d ~/database_dir
BNR

  o.separator 'Compulsory Argument, unless set in a config file'

  o.string '-d', '--database_dir',
           'Read BLAST database from this directory'

  o.separator ''
  o.separator 'Optional Arguments'

  o.string '-f', '--default_db',
           'The Path to the the default database'

  o.string '-n', '--num_threads',
           'Number of threads to use to run a BLAST search'

  o.string '-c', '--config_file',
           'Use the given configuration file'

  o.string '-r', '--require'
           'Load extension from this file'

  o.string '--host',
           'Host to run GeneValidatorApp on'
  
  o.string '-p', '--port'
           'Port to run GeneValidatorApp on'
  
  o.string '-s', '--set',
           'Set configuration value in the config file'
  
  o.bool   '-l', '--list_dbs',
           'List BLAST databases'
  
  o.string '-b', '--blast_bin',
           'Load BLAST+ binaries from this directory'
  
  o.string '-m', '--mafft_bin',
           'Load Mafft binaries from this directory'
  
  o.string '-w', '--web_dir',
           'Path to the web directory (contains ' \
           'supporting files utilised by the app).'

  o.bool   '-D', '--devel'
           'Start GeneValidatorApp in development mode'
           
  o.bool   '-v', '--version',
           'Print version number of GeneValidatorApp that will be loaded' 

  o.on     '-h', '--help',
           'Display this help message'
end

if opts.help?
  puts opts
  exit
end

if opts.version?
  require 'GeneValidatorApp/version'
  puts GeneValidatorApp::VERSION
  exit
end

ENV['RACK_ENV'] = 'development' if opts.devel?

# Exit gracefully on SIGINT.
stty = `stty -g`.chomp
trap('INT') do
  puts ''
  puts 'Aborted.'
  system('stty', stty)
  exit
end

clean_opts = lambda do |hash|
  hash.delete_if { |k, v| k == :set || k == :version || v.nil? }
  hash
end

require 'GeneValidatorApp'
require 'GeneValidatorApp/exceptions'
begin
  GeneValidatorApp.init clean_opts[opts.to_hash]

rescue GeneValidatorApp::CONFIG_FILE_ERROR => e
  puts e
  exit!
rescue GeneValidatorApp::BLAST_BIN_DIR_NOT_FOUND => e
  puts e

  unless opts.blast_bin?
    puts 'You can set the correct value by running:'
    puts '    $ genevalidatorapp -s -b <path_to_blast_bin>'
  end

  exit!
rescue GeneValidatorApp::MAFFT_BIN_DIR_NOT_FOUND => e
  puts e

  unless opts.mafft_bin?
    puts 'You can set the correct value by running:'
    puts '    $ genevalidatorapp -s -m <path_to_mafft_bin>'
  end

  exit!
rescue GeneValidatorApp::DATABASE_DIR_NOT_FOUND => e
  puts e 

  unless opts.database_dir?
    puts 'You can set the correct value by running:'
    puts
    puts '    $ genevalidatorapp -s -d <value>'
    puts
  end

  exit!
rescue GeneValidatorApp::NUM_THREADS_INCORRECT => e
  puts e 

  unless opts.num_threads?
    puts 'You can set the correct value by running:'
    puts
    puts '    $ genevalidatorapp -s -n <value>'
    puts
  end

  exit!
rescue GeneValidatorApp::EXTENSION_FILE_NOT_FOUND => e
  puts e 

  unless opts.require?
    puts 'You can set the correct value by running:'
    puts
    puts '    $ genevalidatorapp -s -r <value>'
    puts
  end

  exit!
rescue GeneValidatorApp::BLAST_NOT_INSTALLED,
       GeneValidatorApp::BLAST_NOT_COMPATIBLE => e
  # Show original error message first.
  puts
  puts e

  # Set a flag so that if we recovered from error resulting config can be
  # saved. Config will be saved unless invoked with -b option.
  opts.fetch_option(:set).value = !bin?

  # Ask user if she already has BLAST+ downloaded or offer to download
  # BLAST+ for her.
  puts
  puts <<MSG
GeneValidatorApp can use NCBI BLAST+ that you may have on your system already, or
download the correct package for itself. Please enter the path to NCBI BLAST+
or press Enter to download.

Press Ctrl+C to quit.
MSG
  puts
  response = Readline.readline('>> ').to_s.strip
  if response.empty?
    puts
    puts 'Installing NCBI BLAST+.'
    puts "RUBY_PLATFORM #{RUBY_PLATFORM}"

    version = GeneValidatorApp::MINIMUM_BLAST_VERSION
    url = case RUBY_PLATFORM
          when /i686-linux/   # 32 bit Linux
            'ftp://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/' \
            "#{version.chop}/ncbi-blast-#{version}-ia32-linux.tar.gz"
          when /x86_64-linux/ # 64 bit Linux
            'ftp://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/' \
            "#{version.chop}/ncbi-blast-#{version}-x64-linux.tar.gz"
          when /darwin/       # Mac
            'ftp://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/' \
            "#{version.chop}/" \
            "ncbi-blast-#{version}-universal-macosx.tar.gz"
          else
            puts <<ERR
------------------------------------------------------------------------
FAILED!! to install NCBI BLAST+.

We currently support Linux and Mac only (both 32 and 64 bit). If you
believe you are running a supported platform, please open a support
ticket titled "#{RUBY_PLATFORM}" at:

https://github.com/IsmailM/GeneValidatorApp/issues
------------------------------------------------------------------------

ERR
          end

    archive = File.join('/tmp', File.basename(url))
    system "wget -c #{url} -O #{archive} && mkdir -p ~/.genevalidatorapp" \
      "&& tar xvf #{archive} -C ~/.genevalidatorapp"
    unless $?.success?
      puts 'Failed to install BLAST+.'
      puts '  You may need to download BLAST+ from - '
      puts '   http://www.ncbi.nlm.nih.gov/blast/Blast.cgi?CMD=Web&PAGE_TYPE=BlastDocs&DOC_TYPE=Download'
      puts "  Please ensure that you download BLAST+ version
      #{GeneValidatorApp::MINIMUM_BLAST_VERSION} or higher."
      exit!
    end
    opts.fetch_option(:bin).value =
      "~/.genevalidatorapp/ncbi-blast-#{version}/bin/"
    retry
  else
    unless File.basename(response) == 'bin'
      response = File.join(response, 'bin')
    end
    opts.fetch_option(:bin).value = File.join(response)
    puts
    retry
  end
rescue GeneValidatorApp::DATABASE_DIR_NOT_SET => e

  # Show original error message.
  puts
  puts e

  # Set a flag so that if we recovered from error resulting config can be
  # saved. Config will be saved unless invoked with -d option.
  opts.fetch_option(:set).value = !database_dir?

  # Ask user for the directory containing sequences or BLAST+
  # databases.
  puts
  puts <<MSG
GeneValidatorApp needs to know where your FASTA files or BLAST+ databases are.
Please enter the path to the relevant directory (default: current directory).

Press Ctrl+C to quit.
MSG

  puts
  response = Readline.readline('>> ').to_s.strip
  opts.fetch_option(:database_dir).value = response
  retry

rescue GeneValidatorApp::NO_BLAST_DATABASE_FOUND => e
  unless list_databases? || list_unformatted_fastas? || make_blast_databases?

    # Print error raised.
    puts
    puts e

    # Offer user to format the FASTA files.
    database_dir = GeneValidatorApp[:database_dir]
    puts
    puts <<MSG
Search for FASTA files (.fa, .fasta, .fna) in '#{database_dir}' and try
creating BLAST+ databases? [y/n] (Default: y).
MSG
    puts
    print '>> '
    response = STDIN.gets.to_s.strip
    unless response.match(/^[n]$/i)
      puts
      puts 'Searching ...'
      if GeneValidatorApp::Database.unformatted_fastas.empty?
        puts "Couldn't find any FASTA files."
        exit!
      else
        formatted = GeneValidatorApp::Database.make_blast_databases
        exit! if formatted.empty? && !set?
        retry unless set?
      end
    else
      exit! unless set?
    end
  end
end

if opts.list_dbs?
  puts 'Databases found:'
  puts GeneValidatorApp::Database.all
  exit
end

if opts.set? || opts.fetch_option(:set).value
  GeneValidatorApp.config.write_config_file
end

GeneValidatorApp.run
