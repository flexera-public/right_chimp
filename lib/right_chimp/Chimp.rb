 #The Chimp class encapsulates the command-line program logic
#
module Chimp
  class Chimp

    attr_accessor :concurrency, :delay, :retry_count, :hold, :progress, :prompt,
                  :quiet, :use_chimpd, :chimpd_host, :chimpd_port, :tags, :array_names,
                  :deployment_names, :script, :all_scripts, :servers, :ssh, :report, :interactive, :action,
                  :limit_start, :limit_end, :dry_run, :group, :job_id, :job_uuid, :verify, :cli_args
    #
    # These class variables control verbosity
    #
    @@verbose     = false
    @@quiet       = false

    #
    # Set up reasonable defaults
    #
    def initialize

      #
      # General configuration options
      #
      @progress     = false
      @prompt       = true
      @verify       = true
      @dry_run      = false
      @interactive  = true

      #
      # Job control options
      #
      @concurrency  = 1
      @delay        = 0
      @retry_count  = 0
      @hold         = false
      @timeout      = 900

      @limit_start  = 0
      @limit_end    = 0

      #
      # Action configuration
      #
      @action            = :action_none
      @group             = :default
      @group_type        = :parallel
      @group_concurrency = 1

      #
      # Options for selecting objects to work on
      #
      @current          = true
      @match_all        = true

      # This is an array of json data for each instance
      @servers          = []

      @arrays           = []
      @tags             = []
      @array_names      = []
      @deployment_names = []
      @template         = nil
      @script           = nil
      @ssh              = nil
      @ssh_user         = "rightscale"
      @report           = nil
      @inputs           = {}
      @set_tags         = []
      @ignore_errors    = false

      @break_array_into_instances = false
      @dont_check_templates_for_script = false

      #
      # chimpd configuration
      #
      @use_chimpd                 = false
      @chimpd_host                = 'localhost'
      @chimpd_port                = 9055
      @chimpd_wait_until_done     = false

      #
      # Will contain the operational scripts we have found
      # In the form: [name, href]
      @op_scripts = []

      #
      # This will contain the href and the name of the script to be run
      # in the form: [name, href]
      @script_to_run = nil
    end

    #
    # Entry point for the chimp command line application
    #
    def run
      queue = ChimpQueue.instance

      arguments = []

      ARGV.each { |arg| arguments << arg.clone }

      self.cli_args=arguments.collect {|param|
        param.gsub(/(?<==).*/) do |match|
          match='"'+match+'"'
        end
      }.join(" ")


      parse_command_line if @interactive

      check_option_validity if @interactive
      disable_logging unless @@verbose


      puts "chimp #{VERSION} executing..." if (@interactive and not @use_chimpd) and not @@quiet

      #
      # Wait for chimpd to complete tasks
      #
      if @chimpd_wait_until_done
        chimpd_wait_until_done
        exit
      end

      #
      # Send the command to chimpd for execution
      #
      if @use_chimpd
        timestamp=Time.now.to_i
        length=6
        self.job_uuid = (36**(length-1) + rand(36**length - 36**(length-1))).to_s(36)
        ChimpDaemonClient.submit(@chimpd_host, @chimpd_port, self,self.job_uuid)
        exit
      else
        #Connect to the Api
        Connection.instance
        if @interactive
          Connection.connect
        else
          Connection.connect_and_cache
        end
      end

      # If we're processing the command ourselves, then go
      # ahead and start making API calls to select the objects
      # to operate upon
      #

      # Get elements if --array has been passed
      get_array_info

      # Get elements if we are searching by tags
      get_server_info

      # At this stage @servers should be populated with our findings
      # Get ST info for all elements
      if not @servers.empty?
        get_template_info unless @servers.empty?

        puts "Looking for the rightscripts (This might take some time)" if (@interactive and not @use_chimpd) and not @@quiet
        get_executable_info
      end

      if Chimp.failure
        #This is the failure point when executing standalone
        Log.error "##################################################"
        Log.error "[#{Chimp.get_job_uuid}] API CALL FAILED FOR:"
        Log.error "[#{Chimp.get_job_uuid}] chimp #{@cli_args} "
        Log.error "[#{Chimp.get_job_uuid}] Run manually!"
        Log.error "##################################################"
        exit 1
      end
      #
      # Optionally display the list of objects to operate on
      # and prompt the user
      #
      if @prompt and @interactive
        list_of_objects = make_human_readable_list_of_objects
        confirm = (list_of_objects.size > 0 and @action != :action_none) or @action == :action_none

        if @script_to_run.nil?
          verify("Your command will be executed on the following:", list_of_objects, confirm)
        else
          verify("Your command \""+@script_to_run.params['right_script']['name']+"\" will be executed on the following:", list_of_objects, confirm)
        end
      end
      #
      # Load the queue with work
      #
      if not @servers.first.nil? and ( not @executable.nil? or @action == :action_ssh or @action == :action_report)
        jobs = generate_jobs(@servers, @server_template, @executable)
        add_to_queue(jobs)
      end

      #
      # Exit early if there is nothing to do
      #
      if @action == :action_none or ( queue.group[@group].nil? || queue.group[@group].size == 0)
        puts "No actions to perform." unless self.quiet
      else
        do_work
      end
    end

    #
    # Load up @array with server arrays to operate on
    #
    def get_array_info
      return if @array_names.empty?

      # The first thing to do here is make an api1.5 call to get the array hrefs.
      arrays_hrefs=get_hrefs_for_arrays(@array_names)
      # Then we filter on all the instances by this href
      all_instances = Connection.all_instances() unless arrays_hrefs.empty?
      if all_instances.nil?
        Log.debug "[#{Chimp.get_job_uuid}] No results from API query"
      else
        arrays_hrefs.each { |href|
          @servers += all_instances.select {|s|
            s['links']['incarnator']['href'] == href
          }
        }

        Log.debug "[#{Chimp.get_job_uuid}] Found #{@servers.count} servers for that array query"

      end
      # The result will be stored (not returned) into @servers
    end

    #
    # Go through each of the various ways to specify servers via
    # the command line (tags, deployments, etc.) and get all the info
    # needed from the RightScale API.
    #
    def get_server_info
      @servers += get_servers_by_tag(@tags) unless tags.empty?
      # Perhaps allow searchign by deployment
      @servers += get_servers_by_deployment(@deployment_names) unless @deployment_names.empty?
    end

    #
    # Get the ServerTemplate info from the API
    #
    def get_template_info
      # If we have a server or an array
      if not (@servers.first.nil? and @array_names.empty?)
        @server_template = detect_server_template(@servers)
      end
    end

    #
    # Get the Executable (RightScript) info from the API
    #
    def get_executable_info
      if not (@servers.empty? )
        if (@script != nil)
          # If script is an uri/url no need to "detect it"
          # https://my.rightscale.com/acct/9202/right_scripts/205347
          if @script =~ /\A#{URI::regexp}\z/
            if not @use_chimpd
              puts "=================================================="
              puts "WARNING! You will be running this script on all "
              puts "server matches! (Press enter to continue)"
              puts "=================================================="
              gets
            end

            script_number = File.basename(@script)

            s=Executable.new
            s.params['right_script']['href']="right_script_href=/api/right_scripts/"+script_number
            #Make an 1.5 call to extract name, by loading resource.
            Log.debug "[#{Chimp.get_job_uuid}] Making API 1.5 call : client.resource(#{s.params['right_script']['href'].scan(/=(.*)/).last.last})"
            begin
              the_name = Connection.client.resource(s.params['right_script']['href'].scan(/=(.*)/).last.last).name
            rescue
              Log.error "[#{Chimp.get_job_uuid}] Failed to make 1.5 call for rightscript href"
            end
            s.params['right_script']['name'] = the_name
            @executable=s
          else
            #If its not an url, go ahead try to locate it in the ST"
            @executable = detect_right_script(@server_template, @script)
          end
        else
          # @script could be nil because we want to run ssh
          if @action == :action_ssh
            puts "Using SSH command: \"#{@ssh}\"" if @action == :action_ssh
          end
        end
      end
    end

    #
    # Parse command line options
    #
    def parse_command_line
      begin
        opts = GetoptLong.new(
          [ '--tag', '-t', GetoptLong::REQUIRED_ARGUMENT ],
          [ '--tag-use-and', '-a', GetoptLong::NO_ARGUMENT ],
          [ '--tag-use-or', '-o', GetoptLong::NO_ARGUMENT ],
          [ '--array', '-r', GetoptLong::REQUIRED_ARGUMENT ],
          [ '--deployment', '-e', GetoptLong::REQUIRED_ARGUMENT ],
          [ '--script', '-s', GetoptLong::OPTIONAL_ARGUMENT ],
          [ '--ssh', '-x', GetoptLong::OPTIONAL_ARGUMENT ],
          [ '--input', '-i', GetoptLong::REQUIRED_ARGUMENT ],
          [ '--set-template', '-m', GetoptLong::REQUIRED_ARGUMENT ],
          [ '--set-tag', '-w', GetoptLong::REQUIRED_ARGUMENT ],
          [ '--report', '-b', GetoptLong::REQUIRED_ARGUMENT ],
          [ '--progress', '-p', GetoptLong::NO_ARGUMENT ],
          [ '--verbose', '-v', GetoptLong::NO_ARGUMENT ],
          [ '--quiet', '-q', GetoptLong::NO_ARGUMENT ],
          [ '--noprompt', '-z', GetoptLong::NO_ARGUMENT ],
          [ '--concurrency', '-c', GetoptLong::REQUIRED_ARGUMENT ],
          [ '--delay', '-d', GetoptLong::REQUIRED_ARGUMENT ],
          [ '--retry', '-y', GetoptLong::REQUIRED_ARGUMENT ],
          [ '--hold', '-7', GetoptLong::NO_ARGUMENT ],
          [ '--dry-run', '-n', GetoptLong::NO_ARGUMENT ],
          [ '--limit', '-l', GetoptLong::REQUIRED_ARGUMENT ],
          [ '--version', '-1', GetoptLong::NO_ARGUMENT ],
          [ '--chimpd', '-f', GetoptLong::OPTIONAL_ARGUMENT ],
          [ '--chimpd-wait-until-done', '-j', GetoptLong::NO_ARGUMENT ],
          [ '--dont-check-templates', '-0', GetoptLong::NO_ARGUMENT ],
          [ '--ignore-errors', '-9', GetoptLong::NO_ARGUMENT ],
          [ '--ssh-user', '-u', GetoptLong::REQUIRED_ARGUMENT ],
          [ '--help', '-h', GetoptLong::NO_ARGUMENT ],
          [ '--group', '-g', GetoptLong::REQUIRED_ARGUMENT ],
          [ '--group-type', '-2', GetoptLong::REQUIRED_ARGUMENT ],
          [ '--group-concurrency', '-3', GetoptLong::REQUIRED_ARGUMENT ],
          [ '--timing-log', '-4', GetoptLong::REQUIRED_ARGUMENT ],
          [ '--timeout', '-5',  GetoptLong::REQUIRED_ARGUMENT ],
          [ '--noverify', '-6', GetoptLong::NO_ARGUMENT ],
          [ '--exact-matching', '-8', GetoptLong::NO_ARGUMENT ]
        )

        opts.each do |opt, arg|
          case opt
            when '--help', '-h'
              help
              exit 0
            when '--tag', '-t'
              @tags << arg
            when '--tag-use-and', '-a'
              @match_all = true
            when '--tag-use-or', '-o'
              @match_all = false
            when '--array', '-a'
              @array_names << arg
            when '--deployment', '-e'
              @deployment_names << arg
            when '--template', '-m'
              @template = arg
            when '--script', '-s'
              set_action(:action_rightscript)
              if arg == ""
                # Empty but not nil means show list of operational scripts to choose from
                @script = ""
              else
                @script = arg
              end
            when '--ssh', '-x'
              set_action(:action_ssh)
              @break_array_into_instances = true
              if arg == ""
                print "Enter SSH command line to execute: "
                @ssh = gets.chomp
              else
                @ssh = arg
              end
            when '--ssh-user', '-u'
              @ssh_user = arg
            when '--input', '-i'
              arg =~ /(.+)=(.+)/
              @inputs[$1]=$2
            when '--set-template', '-m'
              set_action(:action_set)
              @template = arg
            when '--set-tag', '-w'
              set_action(:action_set)
              @set_tags << arg
            when '--report', '-b'
              set_action(:action_report)
              @report = arg
              @@verbose = false
              @@quiet = true
              @break_array_into_instances = true
              @concurrency = 5 if @concurrency == 1
            when '--progress', '-p'
              @progress = @progress ? false : true
            when '--noprompt', '-z'
              @prompt = false
            when '--concurrency', '-c'
              @concurrency = arg.to_i
            when '--delay', '-d'
              @delay = arg.to_i
            when '--hold', '-7'
              @hold = true
            when '--retry', '-y'
              @retry_count = arg.to_i
            when '--limit', '-l'
              @limit_start, @limit_end = arg.split(',')
            when '--verbose', '-v'
              @@verbose = true
              Log.threshold = Logger::DEBUG
            when '--quiet', '-q'
              @@quiet = true
            when '--dont-check-templates', '-0'
              @dont_check_templates_for_script = true
            when '--version'
              puts VERSION
              exit 0
            when '--chimpd'
              @use_chimpd = true
              @chimpd_port = arg.to_i unless arg.empty?
            when '--chimpd-wait-until-done'
              @use_chimpd = true
              @chimpd_wait_until_done = true
            when '--dry-run', '-n'
              @dry_run = true
            when '--ignore-errors', '-9'
              @ignore_errors = true
            when '--group', '-g'
              @group = arg.to_sym
            when '--group-type'
              @group_type = arg.to_sym
            when '--group-concurrency'
              @group_concurrency = arg.to_i
            when '--timing-log'
              @timing_log = arg
            when '--timeout'
              @timeout = arg
            when '--noverify'
              @verify = false
            when '--exact-matching'
              @exact = true
          end
        end

        if @use_chimpd && ( @script.nil? || @script.empty? )
          if @chimpd_wait_until_done == false
            puts "#######################################################"
            puts "ERROR: --script cannot be empty when sending to chimpd"
            puts "#######################################################"
            exit 1
          end
        end


      rescue GetoptLong::InvalidOption => ex
        help
        exit 1
      end

      #
      # Before we're totally done parsing command line options,
      # let's make sure that a few things make sense
      #
      if @group_concurrency > @concurrency
        @concurrency = @group_concurrency
      end
    end

    #
    # Check for any invalid combinations of command line options
    #
    def check_option_validity
      if @hold && !@array_names.empty?
        puts "ERROR: Holding of array objects is not yet supported"
        exit 1
      end

      if @tags.empty? and @array_names.empty? and @deployment_names.empty? and not @chimpd_wait_until_done
        puts "ERROR: Please select the objects to operate upon."
        help
        exit 1
      end

      if not @array_names.empty? and ( not @tags.empty? or not @deployment_names.empty? )
        puts "ERROR: You cannot mix ServerArray queries with other types of queries."
        help
        exit 1
      end
    end

    #
    # Api1.6 equivalent
    #
    def get_servers_by_tag(tags)
      # Take tags and collapse it,
      # Default case, tag is AND
      if @match_all
        t = tags.join("&tag=")
        filter = "tag=#{t}"
        servers = Connection.instances(filter)
      else
        t = tags.join(",")
        filter = "tag=#{t}"
        servers = Connection.instances(filter)
      end

      if servers.nil?
        if @ignore_errors
          Log.warn "[#{Chimp.get_job_uuid}] Tag query returned no results: #{tags.join(" ")}"
        else
          raise "[#{Chimp.get_job_uuid}] Tag query returned no results: #{tags.join(" ")}\n"
        end
      elsif servers.empty?
        if @ignore_errors
          Log.warn "[#{Chimp.get_job_uuid}] Tag query returned no results: #{tags.join(" ")}"
        else
          raise "[#{Chimp.get_job_uuid}] Tag query returned no results: #{tags.join(" ")}\n"
        end
      end

      servers = verify_tagged_instances(servers,tags)

      return(servers)
    end

    #
    # Verify that all returned instances from the API match our tag request
    #
    def verify_tagged_instances(servers,tags)
      array_list = servers
      # servers is an array of hashes
      # verify that each object contains the tags.
      if @match_all
        # has to contain BOTH
        matching_servers = array_list.select { |instance| (tags - instance['tags']).empty? }

      else
        # has to contain ANY
        matching_servers = array_list.select { |instance| tags.any? {|tag| instance['tags'].include?(tag)  }}
      end

      # Shall there be a discrepancy, we need to raise an error and end the run.
      if matching_servers.size != servers.size
        if @ignore_errors
          Log.error "[#{Chimp.get_job_uuid}] #{servers.size - matching_servers.size} instances didnt match tag selection."
          Log.error "[#{Chimp.get_job_uuid}] #{tags.join(" ")}"
          Chimp.set_failure(true)
          Log.error "[#{Chimp.get_job_uuid}] Set failure to true because of discrepancy"

          servers = []
        else
          raise "[#{Chimp.get_job_uuid}] #{servers.size - matching_servers.size} instances didnt match tag selection"
        end
      end

      return servers
    end
    #
    # Parse deployment names and get Server objects
    #
    def get_servers_by_deployment(names)
      servers = []
      all_instances = Connection.all_instances

      if @exact
        result = all_instances.select {|i| names.any? {|n| i['links']['deployment']['name'].eql? n }}
      else
        result = all_instances.select {|i| names.any? {|n| i['links']['deployment']['name'] =~ /#{n}/ }}
      end
      servers = result

      return(servers)
    end

    #
    # Given some array names, return the arrays hrefs
    # Api1.5
    #
    def get_hrefs_for_arrays(names)
      result = []
      arrays_hrefs = []
      if names.size > 0
        names.each do |array_name|
          # Find if arrays exist, if not raise warning.
          # One API call per array
          Log.debug "[#{Chimp.get_job_uuid}] Making API 1.5 call: client.server_arrays.index(:filter => [#{array_name}])"
          result = Connection.client.server_arrays.index(:filter => ["name==#{array_name}"])
          # Result is an array with all the server arrays
          if result.size != 0
            if @exact
              #remove results that do not exactly match
              result.each{ |r|
                if array_names.include?(r.raw['name'])
                  arrays_hrefs += [ r.href ]
                end
              }
            else
              arrays_hrefs += result.collect(&:href)
            end
          else
            if @ignore_errors
              Log.debug "[#{Chimp.get_job_uuid}] Could not find array \"#{array_name}\""
            else
              Log.error "[#{Chimp.get_job_uuid}] Could not find array \"#{array_name}\""
            end
          end
        end
        if ( arrays_hrefs.empty? )
          Log.debug "[#{Chimp.get_job_uuid}] Did not find any arrays that matched!" unless names.size == 1
        end

        return(arrays_hrefs)

      end
    end

    #
    # Given a list of servers
    #
    def detect_server_template(servers)

      Log.debug "[#{Chimp.get_job_uuid}] Looking for server template"
      st = []
      if servers[0].nil?
        return (st)
      end

      st += servers.collect { |s|
        [s['href'],s['server_template']]
      }.uniq {|a| a[0]}

      #
      # We return an array of server_template resources
      # of the type [ st_href, st object ]
      #
      Log.debug "[#{Chimp.get_job_uuid}] Found server templates"

      return(st)
    end

    #
    # This function returns @script_to_run which is extracted from matching
    # the desired script against all server templates or the script URL
    #
    def detect_right_script(st, script)
      Log.debug  "[#{Chimp.get_job_uuid}] Looking for rightscript"
      executable = nil
      # In the event that chimpd find @op_scripts as nil, set it as an array.
      if @op_scripts.nil?
        @op_scripts = []
      end
      if st.nil?
        return executable
      end

      # Take the sts and extract all operational scripts
      @op_scripts = extract_operational_scripts(st)

      # if script is empty, we will list all common scripts
      # if not empty, we will list the first matching one
      if @script == "" and @script != nil
        # list all operational scripts
        reduce_to_common_scripts(st.size)

        script_id = list_and_select_op_script

        # Provide the name + href
        s = Executable.new
        s.params['right_script']['href'] = @op_scripts[script_id][1].right_script.href
        s.params['right_script']['name'] = @op_scripts[script_id][0]
        @script_to_run = s
      else
        # Try to find the rightscript in our list of common operational scripts
        @op_scripts.each  do |rb|
          script_name = rb[0]
          if script_name.downcase.include?(script.downcase)
            # We only need the name and the href
            s = Executable.new
            s.params['right_script']['href'] = rb[1].right_script.href
            s.params['right_script']['name'] = script_name
            @script_to_run = s

            Log.debug "[#{Chimp.get_job_uuid}] Found rightscript"
            return @script_to_run
          end
        end
        #
        # If we reach here it means we didnt find the script in the operationals
        #
        if @script_to_run == nil
          # Search outside common op scripts
          search_for_script_in_sts(script, st)
          if @script_to_run.nil?
            if @interactive
              puts "ERROR: Sorry, didnt find that ( "+script+" ), provide an URI instead"
              puts "I searched in:"
              st.each { |s|
                puts "   *  "+s[1]['name']+"  [Rev"+s[1]['version'].to_s+"]"
              }
              if not @ignore_errors
                exit 1
              end
            else
              Log.error "["+self.job_uuid+"] Sorry, didnt find the script: ( "+script+" )!"
              return nil
            end
          else
            if self.job_uuid.nil?
              self.job_uuid = ""
            end
            Log.warn "["+self.job_uuid+"]\"#{@script_to_run.params['right_script']['name']}\" is not a common operational script!"
            return @script_to_run
          end
        end
      end
    end

    def search_for_script_in_sts(script, st)
      # Loop and look inside every st
      st.each do |s|
        Log.debug "[#{Chimp.get_job_uuid}] Making API 1.5 call: client.resource(#{s[1]['href']})"
        begin
          temp=Connection.client.resource(s[1]['href'])
        rescue
          Log.error "[#{Chimp.get_job_uuid}] Failed to load href for ST"
        end
        temp.runnable_bindings.index.each do |x|
          # Look for first match
          if x.raw['right_script']['name'].downcase.include?(script.downcase)
            Log.debug "[#{Chimp.get_job_uuid}] Found requested righscript: #{script}"
            # Provide the name + href
            s = Executable.new
            s.params['right_script']['href'] = x.raw['links'].find{|i| i['rel'] == 'right_script'}['href']
            s.params['right_script']['name'] = x.raw['right_script']['name']
            @script_to_run = s
          end
        end
      end
      # If we hit here, we never found the desired script
      return
    end

    #
    # Presents the user with a list of scripts contained in @op_scripts
    # and Returns an integer indicating the selection
    #
    #
    def list_and_select_op_script
      puts "List of available operational scripts:"
      puts "------------------------------------------------------------"
      for i in 0..@op_scripts.length - 1
        puts "  %3d. #{@op_scripts[i][0]}" % i
      end
      puts "------------------------------------------------------------"
      while true
        printf "Type the number of the script to run and press Enter (Ctrl-C to quit): "
        script_id = Integer(gets.chomp) rescue -1
        if script_id >= 0 && script_id < @op_scripts.length
          puts "Script choice: #{script_id}. #{@op_scripts[ script_id ][0]}"
          break
        else
          puts "#{script_id < 0 ? 'Invalid input' : 'Input out of range'}."
        end
      end

      return script_id
    end

    #
    # Takes the number of st's to search in,
    # and reduces @op_scripts to only those who are
    # repeated enough times.
    #
    def reduce_to_common_scripts(number_of_st)
        counts = Hash.new 0
        @op_scripts.each { |s| counts[s[0]] +=1 }

        b = @op_scripts.inject({}) do |res, row|
          res[row[0]] ||= []
          res[row[0]] << row[1]
          res
        end

        b.inject([]) do |res, (key, values)|
          res << [key, values.first] if values.size >= number_of_st
          @op_scripts = res
        end
    end

    #
    # Returns all matching operational scripts in the st list passed
    #
    def extract_operational_scripts(st)
      op_scripts = []
      size = st.size
      st.each do |s|
        # Example of s structure
        # ["/api/server_templates/351930003",
        #   {"id"=>351930003,
        #    "name"=>"RightScale Right_Site - 2015q1",
        #    "kind"=>"cm#server_template",
        #    "version"=>5,
        #    "href"=>"/api/server_templates/351930003"} ]
        Log.debug "[#{Chimp.get_job_uuid}] Making API 1.5 call: client.resource (ST)"
        begin
          temp=Connection.client.resource(s[1]['href'])
          Log.debug "[#{Chimp.get_job_uuid}] API 1.5 call client.resource (ST) complete"
          temp.runnable_bindings.index.each do |x|
            # only add the operational ones
            if x.sequence == "operational"
              name = x.raw['right_script']['name']
              op_scripts.push([name, x])
            end
          end
        rescue  Exception => e
          Log.error "[#{Chimp.get_job_uuid}] API 1.5 call client.resource (ST) failed"
          Log.error "[#{Chimp.get_job_uuid}] #{e.message}"
        end
      end

      #We now only have operational runnable_bindings under the script_objects array
      if op_scripts.length < 1
        raise "ERROR: No operational scripts found on the server(s). "
        st.each {|s|
          puts "         (Search performed on server template '#{s[1]['name']}')"
        }
      end
      return op_scripts
    end

    #
    # Load up the queue with work
    #
    def generate_jobs(queue_servers, queue_template, queue_executable)
      counter = 0
      tasks = []
      Log.debug "[#{Chimp.get_job_uuid}] Loading queue..."
      #
      # Configure group
      #
      if not ChimpQueue[@group]
        ChimpQueue.instance.create_group(@group, @group_type, @group_concurrency)
      end

      #
      # Process Server selection
      #
      Log.debug("[#{Chimp.get_job_uuid}] Processing server selection for task creation")

      queue_servers.sort! { |a,b| a['name'] <=> b['name'] }
      queue_servers.each do |server|
        #
        # Handle limiting options
        #
        counter += 1
        next if @limit_start.to_i > 0 and counter < @limit_start.to_i
        break if @limit_end.to_i > 0 and counter > @limit_end.to_i

        #
        # Construct the Server object
        #
        s = Server.new

        s.params['href']                  = server['href']

        s.params['current_instance_href'] = s.params['href']
        s.params['current-instance-href'] = s.params['href']

        s.params['name']                  = server['name']
        s.params['nickname']              = s.params['name']

        s.params['ip_address']            = server['public_ip_addresses'].first
        s.params['ip-address']            = s.params['ip_address']

        s.params['private-ip-address']    = server['private_ip_addresses'].first
        s.params['private_ip_address']    = s.params['private-ip-address']

        s.params['resource_uid']          = server['resource_uid']
        s.params['resource-uid']          = s.params['resource_uid']

        s.params['instance-type']         = server['links']['instance_type']['name']
        s.params['instance_type']         = s.params['instance-type']
        s.params['ec2_instance_type']     = s.params['instance-type']
        s.params['ec2-instance-type']     = s.params['instance-type']

        s.params['dns-name']              = server['public_dns_names'].first
        s.params['dns_name']              = s.params['dns-name']

        s.params['locked']                = server['locked']
        s.params['state']                 = server['state']
        s.params['datacenter']            = server['links']['datacenter']['name']

        # This will be useful for later on when we need to run scripts
        Log.debug "[#{Chimp.get_job_uuid}] Making API 1.5 call: client.resource (SERVER) for task creation"
        begin
          s.object = Connection.client.resource(server['href'])
          Log.debug "[#{Chimp.get_job_uuid}] Making API 1.5 call: client.resource (SERVER) for task creation COMPLETE"
        rescue
          Log.error "[#{Chimp.get_job_uuid}] Failed to load server href via API1.5 for task creation"
        end

        e = nil

        # If @script has been passed
        if queue_executable
          e = ExecRightScript.new(
            :server => s,
            :exec => queue_executable,
            :job_uuid => @job_uuid,
            :inputs => @inputs,
            :timeout => @timeout,
            :verbose => @@verbose,
            :quiet => @@quiet
          )
        elsif @ssh
          e = ExecSSH.new(
            :server => s,
            :ssh_user => @ssh_user,
            :exec => @ssh,
            :verbose => @@verbose,
            :quiet => @@quiet
          )
        elsif @report
          if s.href
            e = ExecReport.new(:server => s, :verbose => @@verbose, :quiet => @@quiet)
            e.fields = @report
          end
        elsif @set_tags.size > 0
          e = ExecSetTags.new(:server => s, :verbose => @@verbose, :quiet => @@quiet)
          e.tags = set_tags
        end

        if e != nil
          e.dry_run = @dry_run
          e.quiet   = @@quiet
          e.status  = Executor::STATUS_HOLDING if @hold

          Log.debug "[#{Chimp.get_job_uuid}] Pushing task (end of control)"
          tasks.push(e)
        end
      end
      return(tasks)
    end

    def add_to_queue(a)
      a.each { |task| ChimpQueue.instance.push(@group, task) }
    end

    #
    # Execute the user's command and provide for retrys etc.
    #
    def queue_runner(concurrency, delay, retry_count, progress)
      queue = ChimpQueue.instance
      queue.max_threads = concurrency
      queue.delay = delay
      queue.retry_count = retry_count
      total_queue_size = queue.size

      puts "Executing..." unless progress or not quiet
      pbar = ProgressBar.new("Executing", 100) if progress
      queue.start

      queue.wait_until_done(@group) do
        pbar.set(((total_queue_size.to_f - queue.size.to_f)/total_queue_size.to_f*100).to_i) if progress
      end

      pbar.finish if progress
    end

    #
    # Set the action
    #
    def set_action(a)
      raise ArgumentError.new "Cannot reset action" unless @action == :action_none
      @action = a
    end

    #
    # Allow user to verify results and retry if necessary
    #
    def verify_results(group = :default)
      failed_workers, results_display = get_results(group)

      #
      # If no workers failed, then we're done.
      #
      return true if failed_workers.empty?

      #
      # Some workers failed; offer the user a chance to retry them
      #
      verify("The following objects failed:", results_display, false)

      while true
        puts "(R)etry failed jobs"
        puts "(A)bort chimp run"
        puts "(I)gnore errors and continue"
        command = gets()

        if command =~ /^a/i
          puts "Aborting!"
          exit 1
        elsif command =~ /^i/i
          puts "Ignoring errors and continuing"
          exit 0
        elsif command =~ /^r/i
          puts "Retrying..."
          ChimpQueue.instance.group[group].requeue_failed_jobs!
          return false
        end
      end
    end

    #
    # Get the results from the QueueRunner and format them
    # in a way that's easy to display to the user
    #
    def get_results(group_name)
      queue = ChimpQueue.instance
      Log.debug("getting results for group #{group_name}")
      results = queue.group[@group].results()
      failed_workers = []
      results_display = []

      results.each do |result|
        next if result == nil

        if result[:status] == :error
          name = result[:host] || "unknown"
          message = result[:error].to_s || "unknown"
          message.sub!("\n", "")
          failed_workers << result[:worker]
          results_display << "#{name.ljust(40)} #{message}"
        end
      end

      return [failed_workers, results_display]
    end

    def print_timings
      ChimpQueue.instance.group[@group].results.each do |task|
        puts "Host: #{task[:host]} Type: #{task[:name]} Time: #{task[:total]} seconds"
      end
    end

    def get_failures
      return get_results(@group)
    end

    #
    # Do work: either by submitting to chimpd
    # or running it ourselves.
    #
    def do_work
      done = false

      while not done
        queue_runner(@concurrency, @delay, @retry_count, @progress)

        if @interactive and @verify
          done = verify_results(@group)
        else
          done = true
        end
      end

      if not @verify
        failed_workers, results_display = get_results(group)
        exit 1 if failed_workers.size > 0
      end

      puts "chimp run complete"
    end

    #
    # Completely process a non-interactive chimp object command
    # This is used by chimpd, when processing a task.
    #
    def process
      Chimp.set_failure(false)
      Chimp.set_job_uuid(self.job_uuid)

      Log.debug "[#{Chimp.get_job_uuid}] Processing task"
      # Add to our "processing" counter

      Log.debug "[#{Chimp.get_job_uuid}] Trying to get array_info" unless Chimp.failure
      get_array_info unless Chimp.failure

      Log.debug "[#{Chimp.get_job_uuid}] Trying to get server_info" unless Chimp.failure
      get_server_info unless Chimp.failure

      Log.debug "[#{Chimp.get_job_uuid}] Trying to get template_info" unless Chimp.failure
      get_template_info unless Chimp.failure

      Log.debug "[#{Chimp.get_job_uuid}] Trying to get executable_info" unless Chimp.failure
      get_executable_info unless Chimp.failure

      # All elements of task have been processed
      ChimpDaemon.instance.semaphore.synchronize do
        ChimpDaemon.instance.proc_counter -= 1
      end

      if Chimp.failure

        Log.error "##################################################"
        Log.error "["+self.job_uuid+"] API CALL FAILED FOR:"
        Log.error "["+self.job_uuid+"] chimp #{@cli_args} "
        Log.error "["+self.job_uuid+"] Run manually!"
        Log.error "##################################################"
        return []
      else
        if @servers.first.nil? or @executable.nil?
          Log.warn "[#{Chimp.get_job_uuid}] Nothing to do for \"chimp #{@cli_args}\"."
          return []
        else
          Log.debug "[#{Chimp.get_job_uuid}] Generating job..."
          return generate_jobs(@servers, @server_template, @executable)
        end
      end
    end

    #
    # Asks for confirmation before continuing
    #
    def ask_confirmation(prompt = 'Continue?', default = false)
      a = ''
      s = default ? '[Y/n]' : '[y/N]'
      d = default ? 'y' : 'n'
      until %w[y n].include? a
        a = ask("#{prompt} #{s} ") { |q| q.limit = 1; q.case = :downcase }
        a = d if a.length == 0
      end
      a == 'y'
    end

    #
    # Connect to chimpd and wait for the work queue to empty, and
    # prompt the user if there are any errors.
    #
    def chimpd_wait_until_done
      local_queue = ChimpQueue.instance
      $stdout.print "Waiting for chimpd jobs to complete for group #{@group}..."

      begin
        while !@dry_run
          local_queue = ChimpQueue.instance

          #
          # load up remote chimpd jobs into the local queue
          # this makes all the standard queue control methods available to us
          #
          sleeping_counter = 0
          while true
            local_queue.reset!

            begin
              all = ChimpDaemonClient.retrieve_group_info(@chimpd_host, @chimpd_port, @group, :all)
            rescue RestClient::ResourceNotFound
              sleep 5
              $stdout.print "\nINFO: Waiting on group #{@group}"
              retry
            end

            ChimpQueue.instance.create_group(@group)
            ChimpQueue[@group].set_jobs(all)

            break if ChimpQueue[@group].done?

            if sleeping_counter % 240 == 0
              $stdout.print "\nWaiting for group #{@group}" unless sleeping_counter == 0
            end
            $stdout.print "."
            $stdout.flush
            sleeping_counter += 5
            sleep 5
          end

          #
          # If verify_results returns true, then ask chimpd to requeue all failed jobs.
          #
          if verify_results(@group)
            break
          else
            ChimpDaemonClient.retry_group(@chimpd_host, @chimpd_port, @group)
          end
        end
      ensure
        #$stdout.print " done\n"
      end
    end

    #
    # Disable rest_connection logging
    #
    def disable_logging
      ENV['REST_CONNECTION_LOG'] = "/dev/null"
      ENV['RESTCLIENT_LOG'] = "/dev/null"
    end

    #
    # Configure the Log object
    #
    def self.set_verbose(v=true, q=false)
      @@verbose = v
      @@quiet = q

      STDOUT.sync = true
      STDERR.sync = true

      Log.threshold= Logger::DEBUG if @@verbose
    end

    def self.verbose?
      return @@verbose
    end

    #
    # Always returns 0. Used for chimpd compatibility.
    #
    def job_id
      return 0
    end

    def self.set_job_uuid(value)
      #This is a current thread variable to avoid cross-talk between threads
      Thread.current[:job_uuid] = value
    end

    def self.get_job_uuid
      return Thread.current[:job_uuid]
    end

    def self.set_failure(status)
      #This is a current thread variable to avoid cross-talk between threads
      Thread.current[:failure] = status
    end

    def self.failure
      return Thread.current[:failure]
    end



    ####################################################
    #private
    ####################################################

    #
    # Allow the user to verify the list of servers that an
    # operation will be run against.
    #
    def verify(message, items, confirm=true)
      puts message
      puts "=================================================="

      i = 0
      items.sort.each do |item|
        i += 1
        puts "  %03d. #{item}" % i
      end

      puts "=================================================="

      if confirm
        puts "Press enter to confirm or ^C to exit"
        gets
      end
    end

    #
    # Verify that the given rightscript_executable (the object corresponding to the script)
    # that is associated with the server_template exists in all servers
    # (No need to check server arrays, they must all have the same template.)
    #
    # Returns: none. Prints a warning if any server does not have the script in its template.
    #
    def warn_if_rightscript_not_in_all_servers(servers, server_template, rightscript_executable)

      return if servers.length < 2 or not server_template or not rightscript_executable

      main_server_template      = server_template
      main_server_template_name = main_server_template.params['nickname']
      main_server_template_href = main_server_template.params['href']

      # Find which server has the specified template (the "main" template)
      server_that_has_main_template = nil
      for i in (0..servers.length - 1)
        if servers[i] and servers[i]['server_template_href'] == main_server_template_href
          server_that_has_main_template = servers[i]
          break
        end
      end
      if not server_that_has_main_template
        puts "internal error validating rightscript presence in all servers"
        return
      end

      some_servers_have_different_template = false
      num_servers_missing_rightscript      = 0

      for i in (0..servers.length - 1)
        next if servers[i].empty?

        this_server_template_href = servers[i]['server_template_href']

        # If the server's template has the same href, this server is good
        next if this_server_template_href == main_server_template_href

        if not some_servers_have_different_template
          some_servers_have_different_template = true
          if not @@quiet
            puts "Note: servers below have different server templates:"
            puts "      - server '#{server_that_has_main_template['nickname']}: "
            if @@verbose
              puts "                template name: '#{main_server_template_name}'"
              puts "                         href: '#{main_server_template_href}'"
            end
          end
        end

        this_server_template = ::ServerTemplate.find(this_server_template_href)
        next if this_server_template == nil
        if not @@quiet
          puts "      - server '#{servers[i]['nickname']}: "
          if @@verbose
            puts "                template name: '#{this_server_template.params['nickname']}'"
            puts "                         href: '#{this_server_template.params['href']}'"
          end
        end

        # Now check if the offending template has the rightscript in question
        has_script = false
        this_server_template.executables.each do |cur_script|
          if rightscript_executable['right_script']['href'] == cur_script['right_script']['href']
            has_script = true
            break
          end
        end
        if not has_script
          if not @@quiet
            puts "    >>  WARNING: The above server's template does not include the execution rightscript!"
          end
          num_servers_missing_rightscript += 1
          if num_servers_missing_rightscript == 1
            if @@verbose
              puts "                 script name: \'#{rightscript_executable['right_script']['name']}\', href: \'#{rightscript_executable['right_script']['href']}\'"
            end
          end
        end
      end
      if some_servers_have_different_template
        if num_servers_missing_rightscript == 0
          puts "Script OK. The servers have different templates, but they all contain the script, \'#{rightscript_executable['right_script']['name']}\'"
        else
          puts "WARNING: total of #{num_servers_missing_rightscript} servers listed do not have the rightscript in their template."
        end
      else
        if not @@quiet
          puts "Script OK. All the servers share the same template and the script is included in it."
        end
      end
    end

    #
    # Generate a human readable list of objects
    #
    def make_human_readable_list_of_objects
      list_of_objects = []

      if @servers and not @servers.first.nil?
        list_of_objects += @servers.map { |s| s['name'] }
      end

      return(list_of_objects)
    end

    #
    # Print out help information
    #
    def help
      puts
      puts "chimp -- a RightScale Platform command-line tool"
      puts
      puts "To select servers using tags:"
      puts "  --tag=<tag>                       example: --tag=service:dataservice=true"
      puts "  --tag-use-and                     'and' all tags when selecting servers (default)"
      puts "  --tag-use-or                      'or' all tags when selecting servers"
      puts
      puts "To select arrays or deployments:"
      puts "  --array=<name>                    array to execute upon"
      puts "  --deployment=<name>               deployment to execute upon"
      puts
      puts "To perform an action, specify one of the following:"
      puts "  --script=[<name>|<uri>|<id>]      name/uri/id of RightScript to run, empty for opscripts list"
      puts "  --report=<field-1>,<field-2>...   produce a report (see below)"
      puts "  --ssh=<command>                   command to execute via SSH"
      puts "  --ssh-user=<username>             username to use for SSH login (default: root)"
      puts
      puts "Action options:"
      puts "  --input=\"<name>=<value>\"          set input <name> for RightScript execution"
      puts
      puts "Execution options:"
      puts "  --group=<name>                    specify an execution group"
      puts "  --group-type=<serial|parallel>    specify group execution type"
      puts "  --group-concurrency=<n>           specify group concurrency, e.g. for parallel groups"
      puts
      puts "  --concurrency=<n>                 number of concurrent actions to perform. Default: 1"
      puts "  --delay=<seconds>                 delay a number of seconds between operations"
      puts
      puts "General options:"
      puts "  --dry-run                         only show what would be done"
      puts "  --ignore-errors                   ignore errors when server selection fails"
      puts "  --retry=<n>                       number of times to retry. Default: 0"
      puts "  --timeout=<seconds>               set the timeout to wait for a RightScript to complete"
      puts "  --progress                        toggle progress indicator"
      puts "  --noprompt                        don't prompt with list of objects to run against"
      puts "  --noverify                        disable interactive verification of errors"
      puts "  --verbose                         be more verbose"
      puts "  --dont-check-templates            don't check for script even if servers have diff. templates"
      puts "  --quiet                           suppress non-essential output"
      puts "  --version                         display version and exit"
      puts
      puts "chimpd options:"
      puts "  --chimpd=<port>                   send jobs to chimpd listening on <port> on localhost"
      puts "  --chimpd-wait-until-done          wait until all chimpd jobs are done"
      puts "  --hold                            create a job in chimpd without executing until requested"
      puts
      puts "Misc Notes:"
      puts "  * If you leave the name of a --script or --ssh command blank, chimp will prompt you"
      puts "  * URIs must be API URIs in the format https://us-3.rightscale.com/acct/<acct>/right_scripts/<script_id>"
      puts "  * The following reporting keywords can be used: ip-address,name,href,private-ip-address,resource_uid,"
      puts "  * ec2-instance-type,datacenter,dns-name,locked,tag=foo"
    end
  end
end
