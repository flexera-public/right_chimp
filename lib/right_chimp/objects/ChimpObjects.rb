#
# Extra classes needed to operate with Chimp
#
module Chimp
  #
  # This class contains all the necessary to make calls to api1.5 via the right_api_client gem
  # or obtain a list of instances via api1.6 calls. 
  #
  class Connection
    #
    # initialize
    # self.connect
    # self.client
    # self.endpoint
    #
    include Singleton
    attr_accessor :client, :all_instances

    def initialize
    end

    def self.connect
      require 'yaml'
      require 'right_api_client'
      begin
        creds = YAML.load_file("#{ENV['HOME']}/.rest_connection/rest_api_config.yaml")

        # Extract the account
        creds[:account] = File.basename(creds[:api_url])

        # Figure out url to hit:
        creds[:api_url] = "https://"+URI.parse(creds[:api_url]).host

        @endpoint = URI.parse(creds[:api_url]).host


        @client = RightApi::Client.new(:email => creds[:user], :password => creds[:pass],
                                        :account_id => creds[:account], :api_url => creds[:api_url],
                                        :timeout => nil)

      rescue
        puts "##############################################################################"
        puts "Error, credentials file: could not be loaded correctly"
        puts "or Connection couldnt be establishhed"
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
        filters_list = "state=operational"
        filters = CGI::escape(filters_list)

        query="/api/instances?view=full&filter="+filters

        get  = Net::HTTP::Get.new(query)
        get['Cookie']        = @client.cookies.map { |key, value| "%s=%s" % [key, value] }.join(';')
        get['X-Api_Version'] = '1.6'
        get['X-Account']     = @client.account_id

        http = Net::HTTP.new(@endpoint, 443)
        http.use_ssl = true
        response   = http.request(get)

        # Validate our response
        @all_instances = validate_response(response)

        # Returns an array of results
        # @all_instances = JSON.parse(response)
      rescue Exception => e
        puts e.message
      end

      return @all_instances
    end

    #
    # Returns every single operational instance in the account, matching the filters passed.
    #
    def self.instances(extra_filters)
      begin
        filters_list = "state=operational&"+extra_filters
        filters = CGI::escape(filters_list)

        query="/api/instances?view=full&filter="+filters

        get  = Net::HTTP::Get.new(query)
        get['Cookie']        = @client.cookies.map { |key, value| "%s=%s" % [key, value] }.join(';')
        get['X-Api_Version'] = '1.6'
        get['X-Account']     = @client.account_id

        http = Net::HTTP.new(@endpoint, 443)
        http.use_ssl = true
        response   = http.request(get)

        # Validate our response
        instances = validate_response(response)

        # Returns an array of results
        # instances = JSON.parse(response.body)
      rescue Exception => e
        puts e.message
      end

      return instances
    end

    # 
    # Provides a way to make an api1.6 call directly
    #
    def self.api16_call(query)
      begin
        get  = Net::HTTP::Get.new(query)
        get['Cookie']        = @client.cookies.map { |key, value| "%s=%s" % [key, value] }.join(';')
        get['X-Api_Version'] = '1.6'
        get['X-Account']     = @client.account_id

        http = Net::HTTP.new(@endpoint, 443)
        http.use_ssl = true
        response = http.request(get)
        # Validate our response
        instances = validate_response(response)

        # response = JSON.parse(response.body)

      rescue Exception => e
        puts e.message
      end

      return instances
    end

    #
    # Verify the results are valid JSON
    #
    def Connection.validate_response(response)
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
              raise "Error: Problem with API request: '#{resp_code} #{result['message']}'" #we know this checkout will fail (branch input, repo name, etc. wrong)
            end
            if result.include? 'Error'
              Log.error "Warning: Got response: '#{resp_code} #{result['Error']}'."
              return {} # Return an empty json
            end
            # extract the most recent commit on designated branch from hash
            Log.debug "We received a valid JSON data, therefore returning it."
            return result
          end

          # if result.is_a?(Hash)
          #   # Operate on a 200 or 404 with valid JSON response, catch error messages from github in json hash
          #   if result.has_key? 'message'
          #     raise "Error: Problem with API request: '#{resp_code} #{result['message']}'" #we know this checkout will fail (branch input, repo name, etc. wrong)
          #   end
          #   if result.has_key? 'Error'
          #     Log.error "Warning: Got response: '#{resp_code} #{result['Error']}'.  Attempting full code checkout anyways!"
          #     return {} # Return an empty json
          #   end
          #   # extract the most recent commit on designated branch from hash
          #   Log.debug "We received a valid JSON data, therefore returning it."
          #   return result
          # end
        rescue JSON::ParserError
          Logger.log "Warning: Expected JSON response but was unable to parse!"
          Logger.log "Warning: #{response.body}!"

          return {} # Return an empty result
        end
      else
        # Any http response code that is not 200 or 404 should error out.
        Log.error "Warning: Got '#{resp_code} #{response.msg}' response from api!  "
        raise "Couldnt contact the API"
      end
    end

  end

  #
  # This class allows to check on the status of any of the tasks created.
  #
  class Task
    #
    # wait_for_state
    # wait_for_completed
    # state
    # href
    #

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
    #
    # initialize
    # href
    # name
    #

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
    #
    # initialize
    # href
    # name
    # nickname
    # ip_address
    # encode_with
    # run_executable
    #

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
      params=options.collect { |k, v| "&inputs[][name]=#{k}&inputs[][value]=#{v}" }.join('&')
      # self is the actual Server object
      task = self.object.run_executable(script_href + params)
      return task
    end
  end
end
