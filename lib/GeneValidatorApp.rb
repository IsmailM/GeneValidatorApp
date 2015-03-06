require 'GeneValidatorApp/database'
require 'GeneValidatorApp/genevalidator'
require 'GeneValidatorApp/logger'
require 'GeneValidatorApp/config'
require 'GeneValidatorApp/version'
require 'GeneValidatorApp/exceptions'
require 'genevalidator/version'

require 'pathname'
require 'yaml'
require 'sinatra/base'
require 'sinatra/cross_origin'
require 'slim'
require 'thin'

module GeneValidatorApp
  # Use a fixed minimum version of BLAST+
  MINIMUM_BLAST_VERSION = '2.2.30+'

  class << self
    attr_reader :public_dir, :tempdir, :config

    # Returns the Rack Environment
    def environment
      ENV['RACK_ENV']
    end

    # Run by the logger method - sets the logger level to verbose if in
    #   development environment
    def verbose?
      @verbose ||= (environment == 'development')
    end

    # Root dir of the App
    def root
      Pathname.new(__FILE__).dirname.parent
    end

    def logger
      @logger ||= Logger.new(STDERR, verbose?)
    end

    # Setting up the environment before running the app...
    def init(config = {})
      @config = Config.new(config)
      init_blast_and_mafft_binaries
      init_database
      load_extension
      check_num_threads
      check_max_characters
      init_gv_tempdir
      init_public_dir
      self
    end

    # Starting the app manually using Thin
    def run
      check_host
      url = "http://#{config[:host]}:#{config[:port]}"
      server = Thin::Server.new(config[:host], config[:port], signals: false) do
        use Rack::CommonLogger if GeneValidatorApp.environment == 'development'
        run GeneValidatorApp
      end
      server.silent = true
      server.backend.start do
        puts '** GeneValidatorApp is ready.'
        puts "   Go to #{url} in your browser and start analysing Genes!"
        puts '   Press CTRL+C to quit.'
        puts
        open_default_browser(url)
        [:INT, :TERM].each do |sig|
          trap sig do
            server.stop!
            puts
            puts
            puts '** Thank you for using GeneValidatorApp :).'
            puts '   Please cite: '
            puts '        Dragan M., Moghul M.I., Priyam A., Wurm Y (in prep).'
            puts '        GeneValidator: identify problematic gene predictions.'
          end
        end
      end
    rescue
      puts '** Oops! There was an error.'
      puts "   Is GeneValidatorApp already accessible at #{url}?"
      puts '   Try running GeneValidatorApp on another port, like so:'
      puts 
      puts '      genevalidatorapp -p 4570.'
    end

    # Set the max characters accepted from the app (for the app templates)
    def max_characters
      (config[:max_characters]) ? config[:max_characters] : 'undefined'
    end

    def [](key)
      config[key]
    end

    # Rack-interface.
    #
    # Inject our logger in the env and dispatch request to our
    # controller.
    def call(env)
      env['rack.logger'] = logger
      App.call(env)
    end

    private

    def open_default_browser(url)
      return if using_ssh?
      if RUBY_PLATFORM =~ /linux/
        `xdg-open #{url}` unless command?('xdg-open') || ENV['DISPLAY']
      elsif RUBY_PLATFORM =~ /darwin/
        `open #{url}`
      end
    end

    def using_ssh?
      true if ENV['SSH_CLIENT'] || ENV['SSH_TTY'] || ENV['SSH_CONNECTION']
    end
    
    def init_blast_and_mafft_binaries
      init_binaries(config[:blast_bin], 'BLAST')
      assert_blast_installed_and_compatible
      init_binaries(config[:mafft_bin], 'Mafft')
      assert_mafft_installed
    end

    def init_binaries(bin_dir, type)
      if bin_dir
        bin_dir = File.expand_path bin_dir
        unless File.exist?(bin_dir) && File.directory?(bin_dir)
          fail BLAST_BIN_DIR_NOT_FOUND, bin_dir if type == 'BLAST'
          fail MAFFT_BIN_DIR_NOT_FOUND, bin_dir if type == 'Mafft'
        end
        logger.debug("Will use #{type} at: #{config[:blast_bin]}")
        export_bin_dir bin_dir
      else 
        logger.debug("Will use #{type} at: $PATH")
      end
    end

    def init_database
      fail DATABASE_DIR_NOT_SET unless config[:database_dir]

      config[:database_dir] = File.expand_path(config[:database_dir])
      unless File.exist?(config[:database_dir]) &&
             File.directory?(config[:database_dir])
        fail DATABASE_DIR_NOT_FOUND, config[:database_dir]
      end

      assert_blast_databases_present_in_database_dir
      logger.debug("Will use BLAST+ databases at: #{config[:database_dir]}")

      Database.scan_databases_dir
      Database.each do |database|
        logger.debug("Found #{database.type.chomp} database" \
                     " '#{database.title.chomp}' at '#{database.name.chomp}'")
      end
    end

    def check_num_threads
      num_threads = Integer(config[:num_threads])
      fail NUM_THREADS_INCORRECT unless num_threads > 0
      logger.debug "Will use #{num_threads} threads to run BLAST."
      if num_threads > 256
        logger.warn "Number of threads set at #{num_threads} is unusually high."
      end
    rescue
      raise NUM_THREADS_INCORRECT
    end

    def check_max_characters
      Integer(config[:max_characters]) if config[:max_characters]
    rescue
      raise MAX_CHARACTERS_INCORRECT
    end

    def load_extension
      return unless config[:require]

      config[:require] = File.expand_path config[:require]
      unless File.exist?(config[:require]) && File.file?(config[:require])
        fail EXTENSION_FILE_NOT_FOUND, config[:require]
      end

      logger.debug("Loading extension: #{config[:require]}")
      require config[:require]
    end

    # Asserts whether mafft is installed.
    def assert_mafft_installed
      fail MAFFT_NOT_INSTALLED unless command? 'mafft'
    end

    def assert_blast_installed_and_compatible
      fail BLAST_NOT_INSTALLED unless command? 'blastdbcmd'
      version = `blastdbcmd -version`.split[1]
      fail BLAST_NOT_COMPATIBLE, version unless version >= MINIMUM_BLAST_VERSION
    end

    def assert_blast_databases_present_in_database_dir
      cmd = "blastdbcmd -recursive -list #{config[:database_dir]}"
      out = `#{cmd}`
      errpat = /BLAST Database error/
      fail NO_BLAST_DATABASE_FOUND, config[:database_dir] if out.empty?
      fail BLAST_DATABASE_ERROR, cmd, out if out.match(errpat) ||
                                             !$?.success?
    end

    # Export bin dir to PATH environment variable.
    def export_bin_dir(bin_dir)
      return unless bin_dir
      return if ENV['PATH'].split(':').include? bin_dir
      ENV['PATH'] = "#{bin_dir}:#{ENV['PATH']}"
    end

    # Creates a Temp directory (starting with 'GeneValidator_') each time
    #   GVapp is started. Within this Temp folder, sub directories are created
    #   in which GeneValidator is run.
    def init_gv_tempdir
      @tempdir = Pathname.new(Dir.mktmpdir('GeneValidator_'))
    end

    # Copy the public folder (in the app root) to the web_dir location - this
    #   web_dir is then used by the app to serve all dependencies...
    def init_public_dir
      @public_dir = Pathname.new(config[:web_dir]) +
                    "GeneValidator_#{Time.now.strftime('%Y%m%d-%H%M%S')}"
      root_public_dir = GeneValidatorApp.root + 'public'
      FileUtils.cp_r(root_public_dir, @public_dir)
    end

    # Check and warn user if host is 0.0.0.0 (default).
    def check_host
      if config[:host] == '0.0.0.0'
        logger.warn 'Will listen on all interfaces (0.0.0.0).' \
                    ' Consider using 127.0.0.1 (--host option).'
      end
    end

    # Return `true` if the given command exists and is executable.
    def command?(command)
      system("which #{command} > /dev/null 2>&1")
    end
  end

  # The Actual App...
  class App < Sinatra::Base
    register Sinatra::CrossOrigin

    configure do
      # We don't need Rack::MethodOverride. Let's avoid the overhead.
      disable :method_override

      # Ensure exceptions never leak out of the app. Exceptions raised within
      # the app must be handled by the app. We do this by attaching error
      # blocks to exceptions we know how to handle and attaching to Exception
      # as fallback.
      disable :show_exceptions, :raise_errors

      # Make it a policy to dump to 'rack.errors' any exception raised by the
      # app so that error handlers don't have to do it themselves. But for it
      # to always work, Exceptions defined by us should not respond to `code`
      # or http_status` methods. Error blocks errors must explicitly set http
      # status, if needed, by calling `status` method.
      enable :dump_errors

      # We don't want Sinatra do setup any loggers for us. We will use our own.
      set :logging, nil

      # This is the app root...
      set :root,          lambda { GeneValidatorApp.root }

      # This is the full path to the public folder...
      set :public_folder, lambda { GeneValidatorApp.public_dir }
    end

    # Set up global variables for the templates...
    before '/' do
      @default_db         = Database.default_db
      @non_default_dbs    = Database.non_default_dbs
      @max_characters     = GeneValidatorApp.max_characters
      @current_gv_version = GeneValidator::VERSION
    end

    get '/' do
      slim :index
    end

    post '/' do
      cross_origin # Required for the API to work...
      RunGeneValidator.init(request.url, params)
      RunGeneValidator.run
    end

    # This error block will only ever be hit if the user gives us a funny
    # sequence or incorrect advanced parameter. Well, we could hit this block
    # if someone is playing around with our HTTP API too.
    error RunGeneValidator::ArgumentError do
      status 400
      slim :"500", layout: false
    end

    # This will catch any unhandled error and some very special errors. Ideally
    # we will never hit this block. If we do, there's a bug in GeneValidatorApp
    # or something really weird going on.
    # TODO: If we hit this error block we show the stacktrace to the user
    # requesting them to post the same to our Google Group.
    error Exception, RunGeneValidator::RuntimeError do
      status 500 # TODO Create another template...
      slim :"500", layout: false
    end

    not_found do
      status 404
      slim :"500" # TODO: Create another Template
    end
  end
end
