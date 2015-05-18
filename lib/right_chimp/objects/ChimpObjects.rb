#
# Extra classes needed to operate with Chimp
#
module Chimp
  #
  # This class contains all the necessary to make calls to api1.5 via the right_api_client gem
  # or obtain a list of instances via api1.6 calls.
  #
  class Connection

    include Singleton
    attr_accessor :client, :all_instances, :retry

    def initialize
    end

    def self.connect_and_cache

      self.start_right_api_client

      puts "Making initial Api1.6 call to cache entries."

      result = self.all_instances
      if result.empty? || result.nil?
        puts "Couldnt contact API1.6 correctly, will now exit."
        exit -1
      else
        puts "API lists #{result.count} operational instances in the account"
      end
    end

    def self.connect
      self.start_right_api_client
    end

    def self.start_right_api_client
      require 'yaml'
      require 'right_api_client'
      begin
        creds = YAML.load_file("#{ENV['HOME']}/.rest_connection/rest_api_config.yaml")

        # Extract the account
        creds[:account] = File.basename(creds[:api_url])

        # Figure out url to hit:
        creds[:api_url] = "https://"+URI.parse(creds[:api_url]).host

        @endpoint = URI.parse(creds[:api_url]).host

        puts "Logging into Api 1.5 right_api_client"

        @client = RightApi::Client.new(:email => creds[:user], :password => creds[:pass],
                                        :account_id => creds[:account], :api_url => creds[:api_url],
                                        :timeout => 60 )
      rescue
        puts "##############################################################################"
        puts "Error: "
        puts " - credentials file could not be loaded correctly"
        puts "or                           "
        puts " - connection couldnt be establishhed"
        puts "##############################################################################"
        exit -1
      end
    end

    def self.client
      @client
    end

    def self.endpoint
      @endpoint
    end

    #
    # Returns every single operational instance in the account
    #
    def self.all_instances()
      begin
        puts "[#{Chimp.get_job_uuid}] Requesting all instances"

        filters_list = "state=operational"
        filters = CGI::escape(filters_list)

        query="/api/instances?view=full&filter="+filters

        @all_instances = Connection.api16_call(query)

      rescue Exception => e
        puts "[#{Chimp.get_job_uuid}] self.all_instaces"
        puts "[#{Chimp.get_job_uuid}] #{e.message}"
      end

      return @all_instances
    end

    #
    # Returns every single operational instance in the account, matching the filters passed.
    #
    def self.instances(extra_filters)
      puts "[#{Chimp.get_job_uuid}] Requesting some instances"
      begin
        filters_list = "state=operational&"+extra_filters
        filters = CGI::escape(filters_list)

        query="/api/instances?view=full&filter="+filters

        instances = Connection.api16_call(query)

      rescue Exception => e
        puts "[#{Chimp.get_job_uuid}] self.instances"
        puts "[#{Chimp.get_job_uuid}] #{e.message}"
      end

      return instances
    end

    #
    # Provides a way to make an api1.6 call directly
    #
    def Connection.api16_call(query)

      @retry = true
      retries = 5
      attempts = 0
      sleep_for = 20

      begin
        get  = Net::HTTP::Get.new(query)
        get['Cookie']        = @client.cookies.map { |key, value| "%s=%s" % [key, value] }.join(';')
        get['X-Api_Version'] = '1.6'
        get['X-Account']     = @client.account_id

        http = Net::HTTP.new(@endpoint, 443)
        http.use_ssl = true

        puts "[#{Chimp.get_job_uuid}] Querying API for: #{query}"


        while attempts < retries
          puts "[#{Chimp.get_job_uuid}] Attempt is: #{attempts.to_s}"
          puts "[#{Chimp.get_job_uuid}] Retry is: #{@retry.to_s}"
          if @retry
            if attempts > 0
              puts "[#{Chimp.get_job_uuid}] Retrying..."
              sleep_time = sleep_for * attempts
              # Add a random amount to avoid staggering calls
              sleep_time += rand(15)

              puts "[#{Chimp.get_job_uuid}] Sleeping between retries for #{sleep_time}"
              sleep(sleep_time)
            end

            puts "[#{Chimp.get_job_uuid}] Attempt # #{attempts+1} at querying the API" unless attempts == 0

            time = Benchmark.measure do
              begin
                puts "[] HTTP Making http request"
                @response = http.request(get)
                puts "[] HTTP Request complete"
		            attempts += 1

	            rescue Exception => e
		              puts "HTTP HEREEEE"
              end

            end

            puts "[#{Chimp.get_job_uuid}] API Request time: #{time.real} seconds"
            puts "[#{Chimp.get_job_uuid}] API Query was: #{query}"

            # Validate API response
            puts "[#{Chimp.get_job_uuid}] Validating..."
            instances = validate_response(@response, query)
          else
            # We dont retry, exit the loop.
            puts "[#{Chimp.get_job_uuid}] Not retrying, exiting the loop."
	    @retry = false

            break
          end
        end

        if attempts == retries

          puts "[#{Chimp.get_job_uuid}] Api call failed more than #{retries} times."

          Chimp.set_failure(true)
          puts "[#{Chimp.get_job_uuid}] Set failure to true because of max retries"

          instances = []
          raise "[#{Chimp.get_job_uuid}] Api call failed more than #{retries} times."
        end

      rescue Exception => e
        puts "[#{Chimp.get_job_uuid}] #{e.message}"
        puts "[#{Chimp.get_job_uuid}] Catched exception on http request to the api, retrying"

        # Failure to be set only on maximum retries
        # Chimp.set_failure(true)

        instances = []
        attempts += 1
        retry
      end

      puts "[#{Chimp.get_job_uuid}] #{instances.count} instances matching" unless instances.nil?

	if instances.nil?
		puts "[#{Chimp.get_job_uuid}] instances is nil!"
	end

      return instances
    end

    #
    # Verify the results are valid JSON
    #
    def Connection.validate_response(response, query)

      resp_code = response.code
      # handle response codes we want to work with (200 or 404) and verify json hash from github
      if resp_code == "200" || resp_code == "404"
        body_data = response.body
        # verify json hash is valid and operate accordingly
        begin
          result = JSON.parse(body_data)
          if result.is_a?(Array)
            # Operate on a 200 or 404 with valid JSON response, catch error messages from github in json hash
            if result.include? 'message'
              puts "[#{Chimp.get_job_uuid}] [CONTENT] Errot: Problem with API request: '#{resp_code} #{response.body}'."
              raise "[#{Chimp.get_job_uuid}] [CONTENT] Error: Problem with API request: '#{resp_code} #{response.body}'"
            end
            if result.include? 'Error'
              puts "[#{Chimp.get_job_uuid}] [CONTENT] Warning BAD CONTENT: Response content: '#{response.body}'."
              return {} # Return an empty json
            end
            # extract the most recent commit on designated branch from hash
            # puts "We received a valid JSON response, therefore returning it."

            @retry = false


            puts "[#{Chimp.get_job_uuid}] Validated and returning size of #{result.size} "
            return result
          end
        rescue JSON::ParserError
          puts "[#{Chimp.get_job_uuid}] Warning: Expected JSON response but was unable to parse!"
          #puts "Warning: #{response.body}!"

          return {} # Return an empty result
        end

      elsif resp_code == "502"
        puts "[#{Chimp.get_job_uuid}] Api returned code: 502"
        puts "[#{Chimp.get_job_uuid}] Query was: #{query}"

        @retry = true

      elsif resp_code == "500"
        puts "[#{Chimp.get_job_uuid}] Api returned code: 500"
        puts "[#{Chimp.get_job_uuid}] Query was: #{query}"

        @retry = true

      elsif resp_code == "504"
          puts "[#{Chimp.get_job_uuid}] Api returned code: 504"
          puts "[#{Chimp.get_job_uuid}] Query was: #{query}"

          @retry = true

      else
        # We are here because response was not 200 or 404
        # Any http response code that is not 200 / 404 / 500 / 502 should error out.
        puts "[#{Chimp.get_job_uuid}] ERROR: Got '#{resp_code} #{response.msg}' response from api!  "
        puts "[#{Chimp.get_job_uuid}] Query was: #{query}"
        raise "[#{Chimp.get_job_uuid}] Couldnt contact the API"
        return {}
      end
    end

  end

  #
  # This class allows to check on the status of any of the tasks created.
  #
  class Task

    attr_writer :tasker
    attr_reader :tasker

    def wait_for_state(desired_state, timeout=900)
      while(timeout > 0)
        state=self.tasker.show.summary
      return true if self.state.match(desired_state)
        friendly_url = "https://"+Connection.endpoint+"/audit_entries/"
        friendly_url += self.href.split(/\//).last
        friendly_url = friendly_url.gsub("ae-","")
        # raise "FATAL error, #{self.tasker.show.summary}\n See Audit: API:#{self.href}, WWW:<a href='#{friendly_url}'>#{friendly_url}</a>\n " if self.state.match("failed")
        raise "FATAL error, #{self.tasker.show.summary}\n See Audit: #{friendly_url}'\n " if self.state.match("failed")
        sleep 30
        timeout -= 30
      end
      raise "FATAL: Timeout waiting for Executable to complete.  State was #{self.state}" if timeout <= 0
    end

    def wait_for_completed(timeout=900)
      wait_for_state("completed", timeout)
    end

    def state
      self.tasker.show.summary
    end

    def href
      self.tasker.href
    end
  end

  #
  # This task contains parameters that describe a script/task to be executed
  #
  class Executable

    attr_writer :params
    attr_reader :params

    def initialize
      @params = {
        "position"=>5,
        "right_script"=>{
          "created_at"=>"",
          "href"=>"dummy_href",
          "updated_at"=>"",
          "version"=>4,
          "is_head_version"=>false,
          "script"=>"",
          "name"=>"dummy_name",
          "description"=>"dummy_description"
          },
          "recipe"=>nil,
          "apply"=>"operational"
        }
    end

    def href
      @params['right_script']['href']
    end
    def name
      @params['right_script']['name']
    end
  end

  #
  # This class holds all necessary information regarding an instance
  # and provides a way of executing a script on  it via the run_executable method.
  #
  class Server

    attr_writer :params, :object
    attr_reader :params, :object

    attr_accessor :run_executable

    def initialize
      @params = {
        "href"                    => "dummy href",
        "current_instance_href"   => nil,
        "current-instance-href "  => nil,
        "name"                    => "dummy name",
        "nickname"                => "dummy nickname",
        "ip_address"              => nil,
        "ip-address"              => nil,
        "private-ip-address"      => nil,
        "aws-id"                  => "",
        "ec2-instance-type"       => "",
        "dns-name"                => "",
        "locked"                  => "",
        "state"                   => "",
        "datacenter"              => nil
      }
      @object = nil
    end

    def href
      @params['href']
    end

    def name
      @params['name']
    end

    def nickname
      @params['nickname']
    end

    def ip_address
      @params['ip_address']
    end

    def encode_with(coder)
      vars = instance_variables.map{|x| x.to_s}
      vars = vars - ['@object']

      vars.each do |var|
        var_val = eval(var)
        coder[var.gsub('@', '')] = var_val
      end
    end

    #In order to run the task, we need to call run_executable on ourselves
    def run_executable(exec, options)
      script_href = "right_script_href="+exec.href
      # Construct the parameters to pass for the inputs
      params=options.collect { |k, v|
        "&inputs[][name]=#{k}&inputs[][value]=#{v}" unless k == :ignore_lock
        }.join('&')

      if options[:ignore_lock]
        params+="&ignore_lock=true"
      end
      # self is the actual Server object
      task = self.object.run_executable(script_href + params)
      return task
    end
  end
end
