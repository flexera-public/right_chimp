#
# ChimpDaemon.rb
#
# Classes for the Chimp Daemon (chimpd)
#

module Chimp
  class ChimpDaemon
    attr_accessor :verbose, :debug, :port, :concurrency, :delay, :retry_count, :dry_run, :logfile, :chimp_queue
    attr_reader :queue, :running

    include Singleton

    def initialize
      @verbose     = false
      @debug       = false
      @port        = 9055
      @concurrency = 50
      @delay       = 0
      @retry_count = 0
      @threads     = []
      @running     = false
      @queue       = ChimpQueue.instance
      @chimp_queue = Queue.new
    end

    #
    # Main entry point for chimpd command line application
    #
    def run
      install_signal_handlers
      parse_command_line

      puts "chimpd #{VERSION} launching with #{@concurrency} workers"
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
            when '--exit', '-x'
            	uri = "http://localhost:9055/admin"
							response = RestClient.post uri, { 'shutdown' => true }.to_yaml
							exit 0
          end
        end
      rescue GetoptLong::InvalidOption => ex
        puts "Syntax: chimpd [--logfile=<name>] [--concurrency=<c>] [--delay=<d>] [--retry=<r>] [--port=<p>] [--verbose]"
        exit 1
      end

      #
      # Set up logging/verbosity
      #
      Chimp.set_verbose(@verbose, @quiet)

      if not @verbose
      	ENV['REST_CONNECTION_LOG'] = "/dev/null"
      	ENV['RESTCLIENT_LOG'] = "/dev/null"
      end

      if @quiet
        Log.threshold = Logger::WARN
      end

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
        :BindAddress  => "localhost",
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
          self.quit
        end
      end
    end

    #
    # Quit by waiting for all chimp jobs to finish, not allowing
    # new jobs on the queue, and killing the web server.
    #
    # TODO: call @queue.quit, but with a short timeout?
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
        c.tags = ["bogus:tag=true"]
        c.run
      rescue StandardError
      end

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
              Log.error "submission processor: group=\"#{group}\" script=\"#{queued_request.script}\": #{ex}"
            end
          end
        }
      end
    end

    #
    # GenericServlet -- servlet superclass
    #
    class GenericServlet < WEBrick::HTTPServlet::AbstractServlet
      def get_verb(req)
        r = req.request_uri.path.split('/')[2]
      end

      def get_id(req)
        uri_parts = req.request_uri.path.split('/')
        id = uri_parts[-2]
        return id
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
      # GET a group by name and status
      # /group/<name>/<status>
      #
      def do_GET(req, resp)
        jobs = {}

        group_name = req.request_uri.path.split('/')[-2]
        filter     = req.request_uri.path.split('/')[-1]

        g = ChimpQueue[group_name.to_sym]
        raise WEBrick::HTTPStatus::NotFound, "Group not found" unless g
        jobs = g.get_jobs_by_status(filter)
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

    end

    #
    # JobServlet - job control
    #
    # HTTP body is a yaml serialized chimp object
    #
    class JobServlet < GenericServlet
      def do_POST(req, resp)
        id      = -1
        job_id  = self.get_id(req)
        verb    = self.get_verb(req)

        payload = self.get_payload(req)
        raise WEBrick::HTTPStatus::PreconditionFailed.new('missing payload') unless payload

        q = ChimpQueue.instance
        group = payload.group

        #
        # Ask chimpd to process a Chimp object directly
        #
        #if verb == 'process' or verb == 'add'
        #  payload.interactive = false
        #  tasks = payload.process
        #  tasks.each do |task|
        #    q.push(group, task)
        #  end

        if verb == 'process' or verb == 'add'
          ChimpDaemon.instance.chimp_queue.push payload
          id = 0
        elsif verb == 'update'
          puts "UPDATE"
          q.get_job(job_id).status = payload.status
        end

        resp.body = {
          'id' => id
        }.to_yaml

        raise WEBrick::HTTPStatus::OK
      end

      def do_GET(req, resp)
        id          = self.get_id(req)
        verb        = self.get_verb(req)
        job_results = "OK"
        queue       = ChimpQueue.instance

        #
        # check for special job ids
        #
        jobs = []
        jobs << queue.get_job(id.to_i)

        jobs = queue.get_jobs_by_status(:running) if id == 'running'
        jobs = queue.get_jobs_by_status(:error)   if id == 'error'
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
      def do_GET(req, resp)
        #
        # First determine the path to the files to serve
        #
        if ENV['CHIMP_TEST'] != 'TRUE'
          template_path = File.join(Gem.dir, 'gems', 'right_chimp-' + VERSION, 'lib/right_chimp/templates')
        else
          template_path = 'lib/right_chimp/templates'
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
          count_jobs_failed  = queue.get_jobs_by_status(:error).size
          count_jobs_done    = queue.get_jobs_by_status(:done).size

          resp.body = @template.result(binding)
          raise WEBrick::HTTPStatus::OK
        end
      end
    end # DisplayServlet
  end # ChimpDaemon
end
