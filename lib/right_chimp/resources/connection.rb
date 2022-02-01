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

      Log.debug "Making initial Api1.6 call to cache entries."

      result = self.all_instances
      if result.empty? || result.nil?
        Log.error "Couldnt contact API1.6 correctly, will now exit."
        exit -1
      else
        Log.debug "API lists #{result.count} operational instances in the account"
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

        @audit_url = creds[:api_url] + "/acct/" + creds[:account]

        @endpoint = URI.parse(creds[:api_url]).host

        Log.debug "Logging into Api 1.5 right_api_client"
        if creds[:refresh_token] then
          # no account id extraction, must be specified in config file
          # refresh_token must be specified in config
          @client = RightApi::Client.new(refresh_token: creds[:refresh_token],
                                         account_id: creds[:account], api_url: creds[:api_url],
                                         timeout: 60, enable_retry: true)
        else
          @client = RightApi::Client.new(email: creds[:user], password: creds[:pass],
                                         account_id: creds[:account], api_url: creds[:api_url],
                                         timeout: 60, enable_retry: true)
        end
      rescue => error
        puts "##############################################################################"
        puts "Error: "
        puts " - credentials file could not be loaded correctly"
        puts "or                           "
        puts " - connection couldnt be established"
        puts "##############################################################################"
        puts error.backtrace
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

    def self.audit_url
      @audit_url
    end

    #
    # Returns every single operational instance in the account
    #
    def self.all_instances()
      begin
        Log.debug "[#{Chimp.get_job_uuid}] Requesting all instances"

        filters_list = "state=operational"
        filters = CGI::escape(filters_list)

        query="/api/instances?view=full&filter="+filters

        all_instances = Connection.api16_call(query)

      rescue Exception => e
        Log.error "[#{Chimp.get_job_uuid}] self.all_instaces"
        Log.error "[#{Chimp.get_job_uuid}] #{e.message}"
      end

      return all_instances
    end

    #
    # Returns every single operational instance in the account, matching the filters passed.
    #
    def self.instances(extra_filters)
      Log.debug "[#{Chimp.get_job_uuid}] Requesting some instances"
      begin
        filters_list = "state=operational&"+extra_filters
        filters = CGI::escape(filters_list)

        query="/api/instances?view=full&filter="+filters

        instances = Connection.api16_call(query)

      rescue Exception => e
        Log.error "[#{Chimp.get_job_uuid}] self.instances"
        Log.error "[#{Chimp.get_job_uuid}] #{e.message}"
      end

      return instances
    end

    #
    # Provides a way to make an api1.6 call directly
    #
    def Connection.api16_call(query)
      Thread.current[:retry] = true
      Thread.current[:response] = nil
      retries = 5
      attempts = 0
      sleep_for = 20

      begin
        get = Net::HTTP::Get.new(query)
        if @client.access_token
          # auth using oauth access token
          get['Authorization'] = 'Bearer ' + @client.access_token
        else
          get['Cookie']        = @client.cookies.map { |key, value| "%s=%s" % [key, value] }.join(';')
        end
        get['X-Api_Version'] = '1.6'
        get['X-Account']     = @client.account_id

        http = Net::HTTP.new(@endpoint, 443)
        http.use_ssl = true

        Log.debug "[#{Chimp.get_job_uuid}] Querying API for: #{query}"

        while attempts < retries
          Log.debug "[#{Chimp.get_job_uuid}] Attempt is: #{attempts.to_s}"
          Log.debug "[#{Chimp.get_job_uuid}] Retry is: #{Thread.current[:retry].to_s}"
          if Thread.current[:retry]
            if attempts > 0
              Log.debug "[#{Chimp.get_job_uuid}] Retrying..."
              sleep_time = sleep_for * attempts
              # Add a random amount to avoid staggering calls
              sleep_time += rand(15)

              Log.debug "[#{Chimp.get_job_uuid}] Sleeping between retries for #{sleep_time}"
              sleep(sleep_time)
            end

            Log.debug "[#{Chimp.get_job_uuid}] Attempt # #{attempts+1} at querying the API" unless attempts == 0

            Log.debug "[#{Chimp.get_job_uuid}] HTTP Making http request"
            start_time = Time.now
            Thread.current[:response] = http.request(get)
            end_time = Time.now
            total_time = end_time - start_time

            Log.debug "[#{Chimp.get_job_uuid}] HTTP Request complete"
            attempts += 1

            Log.debug "[#{Chimp.get_job_uuid}] API Request time: #{total_time} seconds"
            Log.debug "[#{Chimp.get_job_uuid}] API Query was: #{query}"

            # Validate API response
            Log.debug "[#{Chimp.get_job_uuid}] Validating..."
            instances = validate_response(Thread.current[:response], query)
          else
            # We dont retry, exit the loop.
            Log.debug "[#{Chimp.get_job_uuid}] Not retrying, exiting the loop."
            Thread.current[:retry] = false
            break
          end
        end

        if attempts == retries

          Log.error "[#{Chimp.get_job_uuid}] Api call failed more than #{retries} times."

          Chimp.set_failure(true)
          Log.error "[#{Chimp.get_job_uuid}] Set failure to true because of max retries"

          instances = []
          raise "[#{Chimp.get_job_uuid}] Api call failed more than #{retries} times."
        end

        if instances.nil?
          Log.error "[#{Chimp.get_job_uuid}] instances is nil!"
        else
          Log.debug "[#{Chimp.get_job_uuid}] API matched #{instances.count} instances"
        end

      rescue Exception => e
        Log.error "[#{Chimp.get_job_uuid}] #{e.message}"
        Log.error "[#{Chimp.get_job_uuid}] Catched exception on http request to the api, retrying"

        instances = []
        attempts += 1
        retry
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
              Log.error "[#{Chimp.get_job_uuid}] [CONTENT] Errot: Problem with API request: '#{resp_code} #{response.body}'."
              raise "[#{Chimp.get_job_uuid}] [CONTENT] Error: Problem with API request: '#{resp_code} #{response.body}'"
            end
            if result.include? 'Error'
              Log.error "[#{Chimp.get_job_uuid}] [CONTENT] Warning BAD CONTENT: Response content: '#{response.body}'."
              return {} # Return an empty json
            end

            # Log.debug "We received a valid JSON response, therefore returning it."

            Thread.current[:retry] = false

            Log.debug "[#{Chimp.get_job_uuid}] Validated and returning size of #{result.size} "
            return result
          end
        rescue JSON::ParserError
          Log.error "[#{Chimp.get_job_uuid}] Warning: Expected JSON response but was unable to parse!"
          #Log.error "Warning: #{response.body}!"

          return {} # Return an empty result
        end

      elsif resp_code == "502"
        Log.debug "[#{Chimp.get_job_uuid}] Api returned code: 502"
        Log.debug "[#{Chimp.get_job_uuid}] Query was: #{query}"

        Thread.current[:retry] = true

      elsif resp_code == "500"
        Log.debug "[#{Chimp.get_job_uuid}] Api returned code: 500"
        Log.debug "[#{Chimp.get_job_uuid}] Query was: #{query}"

        Thread.current[:retry] = true

      elsif resp_code == "504"
          Log.debug "[#{Chimp.get_job_uuid}] Api returned code: 504"
          Log.debug "[#{Chimp.get_job_uuid}] Query was: #{query}"

          Thread.current[:retry] = true

      else
        # We are here because response was not 200 or 404
        # Any http response code that is not 200 / 404 / 500 / 502 should error out.
        Log.error "[#{Chimp.get_job_uuid}] ERROR: Got '#{resp_code} #{response.msg}' response from api!  "
        Log.error "[#{Chimp.get_job_uuid}] Query was: #{query}"
        raise "[#{Chimp.get_job_uuid}] Couldnt contact the API"
        return {}
      end
    end

  end
end
