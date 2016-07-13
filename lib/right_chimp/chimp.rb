# the Chimp class encapsulates the command-line program logic
#
module Chimp
  # This is the main chimp class
  class Chimp
    attr_accessor :verbose, :quiet, :options

    # set up reasonable defaults
    def initialize
      @verbose = true
      @quiet = false
      @options = {}

      Connection.instance
      Connection.connect
    end

    # entry point for the chimp command line application
    def run
      parse_command_line
      validate_command_line
      results = select_instances
      results.each do |i|
        p i['name']
      end
      # noop
    end

    def parse_command_line
      opt_parser = OptionParser.new do |opt|
        opt.banner = 'Usage: chimp COMMAND [OPTIONS]'
        opt.separator ' '

        ############
        # SELECTORS
        ############
        opt.on('-a', '--arrays NAME', Array, 'what arrays to operate on') do |array_names|
          @options[:arrays] = array_names
        end

        opt.on('-t', '--tags TAGS', Array, 'tags to match against') do |tags|
          @options[:tags] = tags
        end

        opt.on('--tag-use-or', 'USE OR TAG?') do |t|
          @options[:tag_use_or] = t
        end

        opt.on('-d', '--deployments DEPLOYMENT', Array, ' deployments to execute against') do |d|
          @options[:deployments] = d
        end

        ############
        # EXECUTORS
        ############
        opt.on('-s', '--script SCRIPT', 'right_script to execute') do |s|
          @options[:script] = s
        end

        ############
        # CHIMPD options
        ############
        opt.on('--dry-run', '--dry-run', 'do not actually execute anything') do
          @options[:dry_run] = true
        end
        opt.on('--concurrency', '--concurrency 8',
               'how many jobs can chimpd run simultaneously') do |c|
          @options[:concurrency] = c
        end

        opt.on('-h', '--help', 'help') do
          puts opt_parser
        end
      end

      opt_parser.parse!
    end

    # this method verifies that all passed parameters are valid.
    def validate_command_line
      # cannot have tags and arrays
      if @options[:arrays] && @options[:tags]
        raise InvalidSelectionError, 'tags cannot be used with arrays'
      end

      if @options[:deployments] && options[:tags]
        raise InvalidSelectionError, 'tags cannot be used with deployments'
      end

      if @options[:deployments] && options[:arrays]
        raise InvalidSelectionError, 'Deployments cannot be used with arrays'
      end
    end

    # disable ABC for this specific function
    # rubocop:disable Metrics/AbcSize
    def select_instances
      a = Connection.all_instances
      case
      # either by tag
      when @options[:tags]
        if @options[:use_tag_or]
          instances = a.select do |i|
            @options[:tags].any? { |n| i['tags'].include? n }
          end
        else
          instances = a.select do |i|
            (@options[:tags] - i['tags']).empty?
          end
        end
      # either by array name
      when @options[:arrays]
        instances = a.select do |i|
          i['links']['incarnator']['kind'] == 'cm#server_array' &&
            @options[:arrays].any? { |n| i['links']['incarnator']['name'].include? n }
        end
      # either by deployment name
      when @options[:deployments]
        instances = a.select do |i|
          @options[:deployments].any? { |n| i['links']['deployment']['name'].include? n }
        end
      end

      instances
    end
    # rubocop:enable Metrics/AbcSize

    # for compatibility
    def self.read_job_uuid
      0
    end
  end
end
