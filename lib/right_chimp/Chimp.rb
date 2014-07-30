#
# The Chimp class encapsulates the command-line program logic
#

module Chimp
  class Chimp
    attr_accessor :concurrency, :delay, :retry_count, :hold, :progress, :prompt,
                  :quiet, :use_chimpd, :chimpd_host, :chimpd_port, :tags, :array_names,
                  :deployment_names, :script, :servers, :ssh, :report, :interactive, :action,
                  :limit_start, :limit_end, :dry_run, :group, :job_id, :verify

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

      @creds = []
      require 'yaml'
      begin 
        creds=YAML.load_file("#{ENV['HOME']}/.rest_connection/rest_api_config.yaml")
        #
        # Extract the account
        #
        creds[:account]=File.basename(creds[:api_url])
        #
        # Figure out url to hit:
        #
        creds[:api_url]="https://"+URI.parse(creds[:api_url]).host
        @client=RightApi::Client.new(:email => creds[:user], :password => creds[:pass], :account_id => creds[:account], :api_url => creds[:api_url])
      rescue
        puts "##############################################################################"
        puts "Error, credentials file: could not be loaded correctly"
        puts "##############################################################################"
        exit -1
      end

      #
      # Will contain the operational scripts we have found
      # In the form: [name, href]
      @op_scripts                 = []

      #
      # This will contain the href and the name of the script to be run
      # in the form: [name, href]
      @script_to_run       = []

#      RestClient.log = nil
    end

    #
    # Entry point for the chimp command line application
    #
    def run
     # queue = ChimpQueue.instance

      parse_command_line if @interactive
      check_option_validity if @interactive
      #disable_logging unless @@verbose

      puts "chimp #{VERSION} executing..." if (@interactive and not @use_chimpd) and not @@quiet

#      #
#      # Wait for chimpd to complete tasks
#      #
#      if @chimpd_wait_until_done
#        chimpd_wait_until_done
#        exit
#      end
#
#      #
#      # Send the command to chimpd for execution
#      #
#      if @use_chimpd
#        ChimpDaemonClient.submit(@chimpd_host, @chimpd_port, self)
#        exit
#      end
#
#      #
#      # If we're processing the command ourselves, then go
#      # ahead and start making API calls to select the objects
#      # to operate upon
#      #
#      get_array_info


      puts "Looking for servers:"
      get_server_info
      
      puts "Looking for their STs"
      get_template_info

      puts "Looking for the rightscripts"
      get_executable_info

#      if ( ask_confirmation("Proceed?", false))
#        puts "Executing..."
#        puts @script_to_run[0][1]
#        execute_script(@servers,@script_to_run)
#      end

#At this stage we should have all the scripts in @op_scripts
#      #
#      # Optionally display the list of objects to operate on
#      # and prompt the user
#      #
      @prompt and @interactive
        list_of_objects = make_human_readable_list_of_objects
        confirm = (list_of_objects.size > 0 and @action != :action_none) or @action == :action_none
#
        verify("Your command will be executed on the following:", list_of_objects, confirm)
#
#        if @servers.length >= 2 and @server_template and @executable and not @dont_check_templates_for_script
#          warn_if_rightscript_not_in_all_servers @servers, @server_template, @executable
#        end
#      end
#
#      #
#      # Load the queue with work
#      #
#      jobs = generate_jobs(@servers, @arrays, @server_template, @executable)
#      add_to_queue(jobs)
#
#      #
#      # Exit early if there is nothing to do
#      #
#      if @action == :action_none or queue.group[@group].size == 0
#        puts "No actions to perform." unless @@quiet
#      else
#        do_work
#      end
    end

    #
    # Process a non-interactive chimp object command
    # Used by chimpd
    #
    def process
      get_array_info
      get_server_info
      get_template_info
      get_executable_info
      jobs = generate_jobs(@servers, @arrays, @server_template, @executable)
      return(jobs)
    end

    #
    # Get the ServerTemplate info from the API
    #
    def get_template_info
      if not (@servers.empty? and @array_names.empty?)
        @server_template = detect_server_template_new(@servers, @array_names)
        @server_template.each { |st| puts st[0] }
      end
    end

    #
    # Get the Executable (RightScript) info from the API
    #
    def get_executable_info
      if not (@servers.empty? )
        if (@script != nil)
        @executable = detect_right_script_new(@server_template, @script)
        puts "Using SSH command: \"#{@ssh}\"" if @action == :action_ssh
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
          [ '--noverify', '-6', GetoptLong::NO_ARGUMENT ]
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
    # Go through each of the various ways to specify servers via
    # the command line (tags, deployments, etc.) and get all the info
    # needed from the RightScale API.
    #
    def get_server_info
      @servers += get_servers_by_tag(@tags)
      @servers += get_servers_by_deployment(@deployment_names)
#      @servers = filter_out_non_operational_servers(@servers)
    end

    #
    # Load up @array with server arrays to operate on
    #
    def get_array_info
      return if @array_names.empty?

      #
      # Some operations (e.g. ExecSSH) require individual server information.
      # Check for @break_array_into_instances and break up the ServerArray
      # into Servers as necessary.
      #
      if @break_array_into_instances
        Log.debug "Breaking array into instances..."
        @servers += get_servers_by_array(@array_names)
        @array_names = []
      end

      @array_names.each do |array_name|
        Log.debug "Querying API for ServerArray \'#{array_name}\'..."
        a = Ec2ServerArray.find_by(:nickname) { |n| n =~ /^#{array_name}/i }.first
        if not a.nil?
          @arrays << a
        else
          if @ignore_errors
            Log.warn "cannot find ServerArray #{array_name}"
          else
            raise "cannot find ServerArray #{array_name}"
          end
        end
      end
    end

    #
    #
    # Get servers to operate on via a tag query
    #
    # Returns: array of RestConnection::Server objects
    #
    def get_servers_by_tag(tags)
      return([]) unless tags.size > 0
      #
      # The API behaves inconsisntently:
      #
      # [0].resource will be an array if multiple elements are found but
      # it will be one object, i.e. NOT AN ARRAY OF SIZE1 if only one server
      # is found.
      #
      # This way we assure servers is always an array with instance objects
      #
      servers = []

      search_results = @client.tags.by_tag(:resource_type => 'instances', :tags => tags, :match_all => @match_all)[0].resource
      if search_results.kind_of?(Array)
        servers = search_results
      else
        servers << search_results
      end


      if tags.size > 0 and servers.nil? or servers.empty?
        if @ignore_errors
          puts  "Tag query returned no results: #{tags.join(" ")}"
        else
           raise "Tag query returned no results: #{tags.join(" ")}"
        end
      end
#      servers.each do |s|
#        puts s.show.name
#      end
      return(servers)
    end

    #
    # Parse deployment names and get Server objects
    #
    # Returns: array of RestConnection::Server objects
    #
    def get_servers_by_deployment(names)
      servers = []

      if names.size > 0
        names.each do |deployment|
          #
          # Returns an array
          # 
          d = @client.deployments.index(:filter => ["name==#{deployment}"])
          if d == nil
            if @ignore_errors
              puts "cannot find deployment #{deployment}"
            else
              raise "cannot find deployment #{deployment}"
            end
          else
            # It is possible to find more than one deployment matching
            d.each do |dp|  
              dp.servers.index.each do |i|
                #
                # Only store the instance object if its operational
                #
                if i.show.state == "operational"
                  servers << i.current_instance 
                end
              end
            end
          end
        end
      end
      return(servers)
    end

    #
    # Parse array names
    #
    # Returns: array of RestConnection::Server objects
    #
    def get_servers_by_array(names)
      array_servers = []
      if names.size > 0
        names.each do |array_name|
          all_arrays = ::Ec2ServerArray.find_by(:nickname) { |n| n =~ /^#{array_name}/i }

          if all_arrays != nil and all_arrays.first != nil
            all_arrays.first.instances.each do |s|
              array_servers << s
            end
          end
        end
      end

      return(array_servers)
    end


    #
    # ServerTemplate auto-detection
    #
    # Returns: RestConnection::ServerTemplate
    #
    def detect_server_template_new(servers, array_names_to_detect)
      st = []

      servers.each { |s|
        name=s.show.server_template.show.name
        if !(st.empty?)
          #Only store if its a new server template
          if !(st.reduce(:concat).include?(name))
            st.push([name, s.show.server_template])
          end
        else
          st.push([name, s.show.server_template])
        end
      }
      #
      # We return an array of server_template resources
      # of the type [ name, st object ]
      #
      return(st)
    end

    #
    # Excute a script on objects
    # FIXME: to be sent to Chimpqueue instead
    #
    def execute_script(servers,script)

      #
      # Executing just the first script from the array
      #
      script_href="right_script_href="+script[0][1]
      puts script_href

      tasks = []
      # Maybe add the server name to the task list?
      servers.each { |s|
        tasks.push([s.show.name,s.show.run_executable(script_href)])
      }

      begin
        i=0
        tasks_running=tasks.size
        tasks.each { |t|
          #query the api for the state of the task
          state=t[1].show.summary
          if state.include?("ompleted")
            puts t[0]+" - "+ state
            tasks.delete_at(i)
          else
            puts t[0]+" - "+state
          end
          i=i+1
        }
        sleep 10
      end while ( tasks_running > 0 )
      puts "All tasks completed"

    end

    # Look up the RightScript
    #
    # Returns: RestConnection::Executable
    #
    def detect_right_script_new(st, script)
            # if script is empty, we will list all common scripts
            # if not empty, we will list the first matching one
            size = st.size-1

            st.each do |s|
                s[1].show.runnable_bindings.index.each do |x|
                    #Add rightscript objects to the
                    # only add the operational ones
                    name=x.right_script.show.name
                    if x.sequence == "operational"
                        @op_scripts.push([name, x])
                    end
                end
            end

            #We now should only have operational runnable_bindings under the script_objects array
            if @op_scripts.length <= 1
                puts "ERROR: No common operational scripts found on the server(s). "
                st.each {|s| 
                  puts "         (Search performed on server template '#{s[0]}')"
                }
                exit
            end

            # if script is empty, we will list all common scripts
            # if not empty, we will list the first matching one
            if @script == "" and @script != nil
              #list all operational scripts

              #
              # Reduce to only scripts that appear in ALL ST's
              #
              @op_scripts = @op_scripts.select{|i| @op_scripts.grep(i).size > size}

              
              puts "List of available operational scripts:"
              puts "------------------------------------------------------------"
              for i in 1..@op_scripts.length - 1
              puts "  %3d. #{@op_scripts[i][0]}" % i
              end
              puts "------------------------------------------------------------"
              while true
              printf "Type the number of the script to run and press Enter (Ctrl-C to quit): "
                script_id = Integer(gets.chomp) rescue -1
                if script_id > 0 && script_id < @op_scripts.length
                puts "Script choice: #{script_id}. #{@op_scripts[ script_id ][0]}"
                break
                else
                puts "#{script_id < 0 ? 'Invalid input' : 'Input out of range'}."
                end
                end
                # Provide the name + href
                @script_to_run.push([@op_scripts[script_id][0],@op_scripts[script_id][1].right_script.show.href])
                ########################
               #end of the break

            else
              # 
              # Try to find the first one matching, if none matches, try to run from ANY script - FIXME
              # The arrays is filled with  [name_of_the_script , #<RightApi::ResourceDetail resource_type="runnable_binding">]
              # Maybe throw a warning if script is not on the list?
              #

              puts "script specified, looking into the common ones"
              @op_scripts.each  do |rb|
                  script_name=rb[1].right_script.show.name
                  if script_name =~ Regexp.new(script)
                      #We will only push the hrefs for the scripts since its the only ones we care
                      @script_to_run.push([script_name,rb[1].right_script.show.href])
                      puts "Found:" + script_name + ":" +    rb[1].right_script.show.href
                      break
                  end
              end
              #
              # If we reach here it means we didnt find the script in the operationals one
              # At this point we can make a full-on API query for the last revision of the script
              #
              puts "Didnt find it, must be ANY script"
             
              result=@client.right_scripts.index(:filter => ["name==#{script}"] , :latest_only => true)
              if result.nil?
                puts "Sorry, didnt find that"
                exit
              else
                @script_to_run.push([result[0].name , result[0].href]) 
                puts "Found:" +result[0].name + ":" +   result[0].href
              end
            end
    end
    #
    # Look up the RightScript
    #
    # Returns: RestConnection::Executable
    #
    def detect_right_script(st, script)
      executable = nil

      if script == ""
        if not @interactive
          puts "Error: empty --script= option is supported only in interactive mode. Exiting."
          exit 1
        end
        # Find operational scripts that exist in this server template
        op_script_names = ['dummy name']      # Placeholder for #0 since we want to offer choices 1..n
        op_script_hrefs = [ 'dummy href' ]
        st.executables.each do |ex|
            if ex.apply == "operational"
              op_script_names.push( ex.name )
              op_script_hrefs.push( ex.href )
            end
        end
        if op_script_names.length <= 1
          puts "Warning: No operational scripts found on the server(s). "
          puts "         (Search performed on server template '#{st.nickname}')"
        else
          puts "List of available operational scripts in the server template: ('#{st.nickname}')"
          puts "------------------------------------------------------------"
          for i in 1..op_script_names.length - 1
            puts "  %3d. #{op_script_names[i]}" % i
          end
          puts "------------------------------------------------------------"
          while true
            printf "Type the number of the script to run and press Enter (Ctrl-C to quit): "
            op_script_id = Integer(gets.chomp) rescue -1
            if op_script_id > 0 && op_script_id < op_script_names.length
              puts "Script choice: #{op_script_id}. #{op_script_names[ op_script_id ]}"
              break
            else
              puts "#{op_script_id < 0 ? 'Invalid input' : 'Input out of range'}."
            end
          end
          # Provide the href as the input for the block that will do the lookup
          script = op_script_hrefs[ op_script_id ]
        end
      end

      if script
        if script =~ /^http/ or script =~ /^\d+$/
          if script =~ /^\d+$/
            url_prefix = st.params['href'].match( /^.*\/acct\/\d+/)[0]  # extract the 'https://my.rightscale.com/api/acct/<account_id>' part from the template's href
            script = url_prefix + "/right_scripts/#{script}"
          end
          script_URI = script
          Log.debug "Looking for script href \"#{script_URI}\""
          puts
          # First look up the script URI in the template.
          # It *will* be found if we came here from the 'if script = ""' block
          script = st.executables.detect { |ex| ex.href == script }
          if not script
             script_obj = ::RightScript.find(script_URI)
             script_data = {}
             script_data[ 'name' ] = script_obj.params['name']
             script = ::RightScript.new({ :href => script_URI, :right_script => script_data })
          end
        else
          Log.debug "Looking for script \"#{script}\""
          script = st.executables.detect { |ex| ex.name =~ /#{script}/ }
        end

       if script != nil and script['right_script'] != nil
         puts "RightScript: \"#{script['right_script']['name']}\"" if @interactive
       else
         puts "No matching RightScript found!"
         raise "No matching RightScript found!"
       end

       executable = script
      end

      return(executable)
    end

    #
    # Load up the queue with work
    #
    # FIXME this needs to be refactored
    #
    def generate_jobs(queue_servers, queue_arrays, queue_template, queue_executable)
      counter = 0
      tasks = []
      Log.debug "Loading queue..."

      #
      # Configure group
      #
      if not ChimpQueue[@group]
        ChimpQueue.instance.create_group(@group, @group_type, @group_concurrency)
      end

      #
      # Process ServerArray selection
      #
      Log.debug("processing queue selection")
      if not queue_arrays.empty?
        queue_arrays.each do |array|
          instances = filter_out_non_operational_servers(array.instances)

          if not instances
            Log.error("no instances in array!")
            break
          end

          instances.each do |array_instance|
            #
            # Handle limiting options
            #
            counter += 1
            next if @limit_start.to_i > 0 and counter < @limit_start.to_i
            break if @limit_end.to_i > 0 and counter > @limit_end.to_i
            a = ExecArray.new(
              :array => array,
              :server => array_instance,
              :exec => queue_executable,
              :inputs => @inputs,
              :template => queue_template,
              :timeout => @timeout,
              :verbose => @@verbose,
              :quiet => @@quiet
            )
            a.dry_run = @dry_run
            ChimpQueue.instance.push(@group, a)
          end
        end
      end

      #
      # Process Server selection
      #
      Log.debug("Processing server selection")

      queue_servers.sort! { |a,b| a['nickname'] <=> b['nickname'] }
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
        s = ::Server.new
        s.href = server['href']
        s.current_instance_href = server['current_instance_href']
        s.name = server['nickname'] || server['name']
        s.nickname = s.name
        s.ip_address = server['ip-address'] || server['ip_address']
        e = nil

        if queue_executable
          e = ExecRightScript.new(
            :server => s,
            :exec => queue_executable,
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
        elsif queue_template and not clone
          e = ExecSetTemplate.new(
            :server => s,
            :template => queue_template,
            :verbose => @@verbose,
            :quiet => @@quiet
          )
        elsif @report
          if s.href
            s.href = s.href.sub("/current","")
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
    # Filter out non-operational servers
    # Then add operational servers to the list of objects to display
    #
    def filter_out_non_operational_servers(servers)
      Log.debug "Filtering out non-operational servers..."
      servers.reject! { |s| s == nil || s['state'] != "operational" }
      return(servers)
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
    #
    def process
      get_array_info
      get_server_info
      get_template_info
      get_executable_info
      return generate_jobs(@servers, @arrays, @server_template, @executable)
    end

    #
    # Always returns 0. Used for chimpd compatibility.
    #
    def job_id
      return 0
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
          while true
            local_queue.reset!

            begin
              all = ChimpDaemonClient.retrieve_group_info(@chimpd_host, @chimpd_port, @group, :all)
            rescue RestClient::ResourceNotFound
              sleep 5
              retry
            end

            ChimpQueue.instance.create_group(@group)
            ChimpQueue[@group].set_jobs(all)

            break if ChimpQueue[@group].done?

            $stdout.print "."
            $stdout.flush
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

#      if @@verbose == true
#        Log.threshold = Logger::DEBUG
#      elsif @@quiet == true
#        Log.threshold = Logger::WARN
#      else
#        Log.threshold = Logger::INFO
#      end
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

      if @servers
        list_of_objects += @servers.map { |s| s.show.name }
      end

      if @arrays
        @arrays.each do |a|
          i = filter_out_non_operational_servers(a.instances)
          list_of_objects += i.map { |j| j['nickname'] }
        end
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
      puts "  --verbose                         display rest_connection log messages"
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
      puts "  * You cannot operate on array instances by selecting them with tag queries"
      puts "  * URIs must be API URIs in the format https://my.rightscale.com/api/acct/<acct>/ec2_server_templates/<id>"
      puts "  * The following reporting keywords can be used: nickname, ip-address, state, server_type, href"
      puts "    server_template_href, deployment_href, created_at, updated_at"
    end
  end
end
