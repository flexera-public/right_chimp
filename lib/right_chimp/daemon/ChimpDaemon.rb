#
# ChimpDaemon.rb
#
# Classes for the Chimp Daemon (chimpd)
#

module Chimp
  class ChimpDaemon

    attr_accessor :verbose, :debug, :port, :concurrency, :delay, :retry_count,
                  :dry_run, :logfile, :chimp_queue, :proc_counter, :semaphore,
                  :bind_address
    attr_reader :queue, :running

    include Singleton

    def initialize
      @verbose     = false
      @debug       = false
      @port        = 9055
      @bind_address = "localhost"
      @concurrency = 50
      @delay       = 0
      @retry_count = 0
      @threads     = []
      @running     = false
      @queue       = ChimpQueue.instance
      @chimp_queue = Queue.new
      @semaphore   = Mutex.new

      @proc_counter= 0

      #Connect to the API
      Connection.instance
    end

    #
    # Main entry point for chimpd command line application
    #
    def run
      install_signal_handlers
      parse_command_line

      #puts "chimpd #{VERSION} launching with #{@concurrency} workers"
      puts "Loading... please wait"
      spawn_queue_runner
      spawn_webserver
      spawn_chimpd_submission_processor
      run_forever
    end

    #
    # Parse chimpd command line options
    #
    def parse_command_line
      begin
        opts = GetoptLong.new(
          [ '--logfile', '-l',      GetoptLong::REQUIRED_ARGUMENT ],
          [ '--verbose', '-v',      GetoptLong::NO_ARGUMENT ],
          [ '--quiet',   '-q',      GetoptLong::NO_ARGUMENT ],
          [ '--concurrency', '-c',  GetoptLong::REQUIRED_ARGUMENT ],
          [ '--delay', '-d',        GetoptLong::REQUIRED_ARGUMENT ],
          [ '--retry', '-y',        GetoptLong::REQUIRED_ARGUMENT ],
          [ '--port', '-p',         GetoptLong::REQUIRED_ARGUMENT ],
          [ '--bind-address', '-b', GetoptLong::REQUIRED_ARGUMENT ],
          [ '--help', '-h',         GetoptLong::NO_ARGUMENT ],
          [ '--exit', '-x', 				GetoptLong::NO_ARGUMENT ]
        )

        opts.each do |opt, arg|
          case opt
            when '--logfile', '-l'
              @logfile = arg
              Log.logger = Logger.new(@logfile)
            when '--concurrency', '-c'
              @concurrency = arg.to_i
            when '--delay', '-d'
              @delay = arg.to_i
            when '--retry', '-y'
              @retry_count = arg.to_i
            when '--verbose', '-v'
              @verbose = true
            when '--quiet',   '-q'
              @quiet = true
            when '--port', '-p'
              @port = arg
            when '--bind-address', '-b'
              @bind_address = arg.to_s
            when '--help', '-h'
              help
            when '--exit', '-x'
            	uri = "http://localhost:#{@port}/admin"
							response = RestClient.post uri, { 'shutdown' => true }.to_yaml
							exit 0
          end
        end
      rescue GetoptLong::InvalidOption => ex
        puts "Syntax: chimpd [--logfile=<name>] [--concurrency=<c>] [--delay=<d>] [--retry=<r>] [--port=<p>] [--bind-address=<addr> ] [--verbose]"
        exit 1
      end

      #
      # Set up logging/verbosity
      #
      Chimp.set_verbose(@verbose, @quiet)

      if not @verbose
      	ENV['REST_CONNECTION_LOG'] = "/dev/null"
      	ENV['RESTCLIENT_LOG'] = "/dev/null"
        Log.threshold= Logger::INFO
      else
        Log.threshold= Logger::DEBUG
      end

      if @quiet
        Log.threshold = Logger::WARN
      end
    end

    #
    # Print out help information
    #
    def help
      puts
      puts  "chimpd -- a RightScale Platform command-line tool"
      puts
      puts  "Syntax: chimpd [--logfile=<name>] [--concurrency=<c>] [--delay=<d>] [--retry=<r>] [--port=<p>] [--bind-address=<addr> ] [--verbose]"
      puts
      puts  "Options:"
      puts
      puts  " --logfile=<name>            Specifiy the desired log location"
      puts  " --concurrency=<n>           Specify the level of concurrent actions"
      puts  " --delay=<n>                 Specify the number of seconds to wait before executing the action"
      puts  " --retry=<r>                 Specify the number of times chimpd should retry executing the action"
      puts
      puts  " --verbose                   Run chimpd in verbose mode."
      puts  " --quiet                     Supress non-essential output"
      puts
      puts  " --port=<port>               Specify the port number for chimpd to listen on (default: 9055)"
      puts  " --bind-address=<addr>       Specify an interface address for chimpd to bind to.  0.0.0.0 allows all, default is 'localhost'"
      puts
      puts  " --help                      Displays this menu"
      puts
      exit 0
    end

    #
    # Spawn the ChimpQueue threads
    #
    def spawn_queue_runner
      @queue.max_threads = @concurrency
      @queue.delay = @delay
      @queue.retry_count = @retry_count
      @queue.start
      @running = true
    end

    #
    # Spawn a WEBrick Web server
    #
    def spawn_webserver
      opts = {
        :BindAddress  => @bind_address,
        :Port         => @port,
        :MaxClients   => 500,
        :RequestTimeout => 120,
        :DoNotReverseLookup => true
      }

      if not @verbose
        opts[:Logger] = WEBrick::Log.new("/dev/null")
        opts[:AccessLog] = [nil, nil]
      end

      @server = ::WEBrick::HTTPServer.new(opts)
      @server.mount('/',         DisplayServlet)
      @server.mount('/display',  DisplayServlet)
      @server.mount('/job',      JobServlet)
      @server.mount('/group',    GroupServlet)
      @server.mount('/admin',    AdminServlet)

      #
      # WEBrick threads
      #
      @threads << Thread.new(1001) do
        @server.start
      end
    end

    #
    # Process requests forever until we're killed
    #
    def run_forever
      @running = true
      while @running
        @threads.each do |t|
          t.join(5)
        end
      end
    end

    #
    # Trap signals to exit cleanly
    #
    def install_signal_handlers
      ['INT', 'TERM'].each do |signal|
        trap(signal) do
          puts "Terminating..."
          self.quit
        end
      end
    end

    #
    # Quit by waiting for all chimp jobs to finish, not allowing
    # new jobs on the queue, and killing the web server.
    #
    def quit
      @running = false
      @server.shutdown
      sleep 5
      exit 0
    end

    #
    # Spawn threads to process submitted requests
    #
    def spawn_chimpd_submission_processor
      n = @concurrency/4
      n = 10 if n < 10
      Log.debug "Logging into API..."

      #
      # There is a race condition logging in with rest_connection.
      # As a workaround, do a tag query first thing when chimpd starts.
      #
      begin
        c = Chimp.new
        c.interactive = false
        c.quiet = true
        #c.tags = ["bogus:tag=true"]
        c.run
      rescue StandardError
      end

      puts "chimpd #{VERSION} launched with #{@concurrency} workers"

      Log.debug "Spawning #{n} submission processing threads"

      (1..n).each do |n|
        @threads ||=[]
        @threads << Thread.new {

          while true
            begin


              queued_request = @chimp_queue.pop
              group = queued_request.group
              queued_request.interactive = false
              tasks = queued_request.process
              tasks.each do |task|
                ChimpQueue.instance.push(group, task)
              end

            rescue StandardError => ex
                puts ex.backtrace
              Log.error " submission processor: group=\"#{group}\" script=\"#{queued_request.script}\": #{ex}"
            end
          end
        }
      end
    end

    #
    # GenericServlet -- servlet superclass
    #
    class GenericServlet < WEBrick::HTTPServlet::AbstractServlet
      #
      # get_verb
      # get_id
      # get_payload
      #
      def get_verb(req)
        r = req.request_uri.path.split('/')[2]
      end

      def get_id(req)
        uri_parts = req.request_uri.path.split('/')
        id = uri_parts[-2]
        return id
      end

      def get_job_uuid(req)
        string = req.body.scan(/job_uuid: .{6}/).last
        job_uuid = string.scan(/ (.{6})/).last.last
        return job_uuid
      end
      #
      # Get the body of the request-- assume YAML
      #
      def get_payload(req)
        begin
          return YAML::load(req.body)
        rescue StandardError => ex
          return nil
        end
      end
    end # GenericServlet

    #
    # AdminServlet - admin functions
    #
    class AdminServlet < GenericServlet
      #
      # get do_POST
      #
      def do_POST(req, resp)
        payload = self.get_payload(req)
        shutdown = payload['shutdown'] || false

        if shutdown == true
        	ChimpDaemon.instance.quit
        end

        raise WEBrick::HTTPStatus::OK
      end
    end # AdminServlet

    #
    # GroupServlet - group information and control
    #
    # http://localhost:9055/group/default/running
    #
    class GroupServlet < GenericServlet
      #
      # do_GET
      # do_POST
      #

      #
      # GET a group by name and status
      # /group/<name>/<status>
      #
      def do_GET(req, resp)
        jobs = []
        Log.debug 'get group info'

        group_name = req.request_uri.path.split('/')[-2]
        filter     = req.request_uri.path.split('/')[-1]
        # Quickly check processing jobs just in case
        # Instance the entire queue
        q = ChimpQueue.instance
        g2 = q.processing[group_name.to_sym]

        if g2
          Log.debug 'Found processing job(s): ' + g2.inspect
        else
          Log.debug 'not found any processing jobs for that group: ' + g2.inspect
        end

        g = ChimpQueue[group_name.to_sym]
        raise WEBrick::HTTPStatus::NotFound, 'Group not found' unless g || g2
        jobs = g.get_jobs_by_status(filter) if g

        # If there are processing jobs, add them as dummy executions.
        if g2
          Log.debug 'Group: ' + group_name + ' is processing:'
          g2.each do |job|
            Log.debug 'Job: ' + job
            j = ExecRightScript.new(group: group_name, job_uuid: job)
            jobs.push j
          end
        end

        resp.body = jobs.to_yaml

        raise WEBrick::HTTPStatus::OK
      end

      #
      # POST to a group to trigger a group action
      # /group/<name>/<action>
      #
      def do_POST(req, resp)
        group_name = req.request_uri.path.split('/')[-2]
        filter     = req.request_uri.path.split('/')[-1]
        payload    = self.get_payload(req)

        if filter == 'create'
          ChimpQueue.instance.create_group(group_name, payload['type'], payload['concurrency'])

        elsif filter == 'retry'
          group = ChimpQueue[group_name.to_sym]
          raise WEBrick::HTTPStatus::NotFound, "Group not found" unless group

          group.requeue_failed_jobs!
          raise WEBrick::HTTPStatus::OK

        else
          raise WEBrick::HTTPStatus::PreconditionFailed.new("invalid action")
        end
      end
    end # GroupServlet

    #
    # JobServlet - job control
    #
    # HTTP body is a yaml serialized chimp object
    #
    class JobServlet < GenericServlet
      #
      # do_POST
      # do_GET
      #

      def do_POST(req, resp)
        id      = -1
        # we don't know the job_id because we cant guess how many tasks one call creates.
        job_id  = self.get_id(req)
        job_uuid= self.get_job_uuid(req)
        verb    = self.get_verb(req)

        payload = self.get_payload(req)
        raise WEBrick::HTTPStatus::PreconditionFailed.new('missing payload') unless payload

        q = ChimpQueue.instance
        group = payload.group

        #
        # Ask chimpd to process a Chimp object directly
        #
        if verb == 'process' or verb == 'add'
          # comment the next line to GET STUCK IN PROCESSING forever
          ChimpDaemon.instance.chimp_queue.push payload
          ChimpDaemon.instance.semaphore.synchronize do
            # While we are at it, we will store these processing jobs to prevent issues in the event
            # of a very slow API response.
            q.processing[payload.group] = [] if q.processing[payload.group].nil?
            q.processing[payload.group].push(payload.job_uuid)

            ChimpDaemon.instance.proc_counter += 1
          end

          Log.debug 'Tasks in the processing queue:' + ChimpDaemon.instance.proc_counter.to_s
          Log.debug 'Pocessing:'
          Log.debug q.processing.inspect
        elsif verb == 'update'
          puts 'UPDATE'
          q.get_job(job_id).status = payload.status
        end

        resp.body = {
          'job_uuid' => job_uuid,
          'id' => job_id
        }.to_yaml

        raise WEBrick::HTTPStatus::OK
      end

      def do_GET(req, resp)
        id          = self.get_id(req)
        verb        = self.get_verb(req)
        job_results = 'OK'
        queue       = ChimpQueue.instance

        #
        # check for special job ids
        #
        jobs = []
        jobs << queue.get_job(id.to_i)

        jobs = queue.get_jobs_by_status(:running) if id == 'running'
        jobs = queue.get_jobs_by_status(:error)   if id == 'error'
        jobs = queue.get_jobs_by_status(:holding) if id == 'holding'
        jobs = queue.get_jobs                     if id == 'all'

        raise WEBrick::HTTPStatus::PreconditionFailed.new('invalid or missing job_id #{id}') unless jobs.size > 0

        #
        # ACK a job -- mark it as successful even if it failed
        #
        if req.request_uri.path =~ /ack$/
          jobs.each do |j|
            j.status = Executor::STATUS_DONE
          end

          resp.set_redirect( WEBrick::HTTPStatus::TemporaryRedirect, req.header['referer'])

        #
        # queue a job
        #
        elsif req.request_uri.path =~ /queue$/
          jobs.each do |j|
            j.queue
          end

          resp.set_redirect( WEBrick::HTTPStatus::TemporaryRedirect, req.header['referer'])

        #
        # retry a job
        #
        elsif req.request_uri.path =~ /retry$/
          jobs.each do |j|
            j.requeue
          end

          resp.set_redirect( WEBrick::HTTPStatus::TemporaryRedirect, req.header['referer'])

        #
        # cancel an active job
        #
        elsif req.request_uri.path =~ /cancel$/
          jobs.each do |j|
          	j.cancel if j.respond_to? :cancel
          end

        	resp.set_redirect( WEBrick::HTTPStatus::TemporaryRedirect, req.header['referer'])

        #
        # produce a report
        #
        elsif req.request_uri.path =~ /report$/
          results = ["group_name,type,job_id,script,target,start_time,end_time,total_time,status"]
          jobs.each do |j|
            results << [j.group.group_id, j.class.to_s.sub("Chimp::",""), j.job_id, j.info, j.target, j.time_start, j.time_end, j.get_total_exec_time, j.status].join(",")
          end

          queue.group.values.each do |g|
            results << [g.group_id, g.class.to_s.sub("Chimp::",""), "", "", "", g.time_start, g.time_end, g.get_total_exec_time, ""].join(",")
          end

          job_results = results.join("\n") + "\n"

          resp['Content-type'] = "text/csv"
          resp['Content-disposition'] = "attachment;filename=chimp.csv"
        end

        #
        # return a list of the results
        #
        resp.body = job_results
        raise WEBrick::HTTPStatus::OK
      end
    end # JobServlet

    #
    # DisplayServlet
    #
    class DisplayServlet < GenericServlet
      #
      # do_GET
      #

      def do_GET(req, resp)
        #
        # First determine the path to the files to serve
        #
        if ENV['CHIMP_TEST'] != 'TRUE'
          template_path = File.expand_path('../templates', __dir__)
        else
          template_path = 'lib/right_chimp/templates'
        end

        #
        # Check if we are asked for stats
        #
        if req.request_uri.path =~ /stats$/
          queue = ChimpQueue.instance
          stats = ""
          stats << "running: #{queue.get_jobs_by_status(:running).size} / "
          stats << "waiting: #{queue.get_jobs_by_status(:none).size} / "
          stats << "failed: #{queue.get_jobs_by_status(:error).size} / "
          stats << "done: #{queue.get_jobs_by_status(:done).size} / "
          stats << "processing: #{ChimpDaemon.instance.proc_counter.to_i} / "
          stats << "\n"

          resp.body = stats

          raise WEBrick::HTTPStatus::OK
        end

        if req.request_uri.path =~ /stats\.json$/
          # instance the queue
          queue = ChimpQueue.instance

          stats_hash = {"running" => queue.get_jobs_by_status(:running).size,
                        "waiting" => queue.get_jobs_by_status(:none).size,
                        "failed" => queue.get_jobs_by_status(:error).size,
                        "done" => queue.get_jobs_by_status(:done).size,
                        "processing" => ChimpDaemon.instance.proc_counter.to_i,
                        "holding" => queue.get_jobs_by_status(:holding).size
                      }

          resp.body = JSON.generate(stats_hash)

          raise WEBrick::HTTPStatus::OK
        end

        if req.request_uri.path =~ /jobs\.json$/
          #instance the queue
          queue = ChimpQueue.instance

          job_types = [ :running, :error, :done ]

          jobs = {}

          job_types.each do |type|
            jobs[type] = queue.get_jobs_by_status(type).map do |job|
              { :id => job.job_id,
                :uuid => job.job_uuid,
                :server => job.server.name,
                :script => job.info,
                :audit_entry_url => job.audit_entry_url
              }
            end
          end

          resp.body = jobs.to_json

          raise WEBrick::HTTPStatus::OK
        end

        if req.request_uri.path =~ /jobs\.json\/id\/\d+$/

          job_id = File.basename(req.request_uri.path)
          queue = ChimpQueue.instance

          res = queue.get_job(job_id)

          case res
          when ExecRightScript

            result = {}
            result[:id] = job_id
            result[:uuid] = res.job_uuid
            result[:status] = res.status
            result[:server] = res.server.name
            result[:script] = res.info
            result[:audit_entry_url] = res.audit_entry_url

            resp.body = result.to_json
          end

          raise WEBrick::HTTPStatus::OK

        end
        #
        # Attempt to return just 1 job_UUID data
        #
        if req.request_uri.path =~ /jobs\.json\/uuid\/*\w{6}$/

          uuid = File.basename(req.request_uri.path)
          # instance the queue
          queue = ChimpQueue.instance

          res = queue.get_jobs_by_uuid(uuid)

          jobs = {}

          res.each_with_index do |r, i|
            jobs[i] = { id: r.job_id,
                        uuid: r.job_uuid,
                        status: r.status,
                        server: r.server.name,
                        script: r.info,
                        audit_entry_url: r.audit_entry_url
                      }
          end

          resp.body = jobs.to_json

          raise WEBrick::HTTPStatus::OK
        end

        #
        # Check for static CSS files and serve them
        #
        if req.request_uri.path =~ /\.(css|js)$/
          filename = req.request_uri.path.split('/').last
          resp.body = File.read(File.join(template_path, filename))
          raise WEBrick::HTTPStatus::OK
        else

          #
          # Otherwise process ERB template
          #
          job_filter = self.get_verb(req) || "running"

          if not @template
            @template = ERB.new(File.read(File.join(template_path, "all_jobs.erb")), nil, ">")
          end

          queue = ChimpQueue.instance
          jobs = queue.get_jobs
          group_name = nil

          if job_filter == "group"
            group_name = req.request_uri.path.split('/')[-1]
            g = ChimpQueue[group_name.to_sym]
            jobs = g.get_jobs if g
          end

          count_jobs_running = queue.get_jobs_by_status(:running).size
          count_jobs_queued  = queue.get_jobs_by_status(:none).size
          count_jobs_holding  = queue.get_jobs_by_status(:holding).size
          count_jobs_failed  = queue.get_jobs_by_status(:error).size
          count_jobs_done    = queue.get_jobs_by_status(:done).size
          count_jobs_processing = queue.get_jobs_by_status(:processing).size

          resp.body = @template.result(binding)
          raise WEBrick::HTTPStatus::OK
        end
      end
    end # DisplayServlet
  end # ChimpDaemon
end
