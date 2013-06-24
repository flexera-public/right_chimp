module Chimp
  #
  # The ChimpDaemonClient contains the code for communicating with the
  # RESTful chimpd Web service
  #
  class ChimpDaemonClient
    #
    # Submit a Chimp object to a remote chimpd
    #
    def self.submit(host, port, chimp_object)
      uri = "http://#{host}:#{port}/job/process"
      attempts = 3

      begin
        response = RestClient.post uri, chimp_object.to_yaml

        if response.code > 199 and response.code < 300
          id = YAML::load(response.body)['id']
          return true
        else
          $stderr.puts "WARNING: error submitting to chimpd! response code: #{reponse.code}"
          return false
        end

      rescue RestClient::RequestTimeout => ex
        $stderr.puts "WARNING: Request timeout talking to chimpd for job #{chimp_object.script}: #{ex.message} (#{ex.http_code})"
        attempts -= 1
        sleep 5 and retry if attempts > 0
        return false

      rescue RestClient::InternalServerError => ex
        $stderr.puts "WARNING: Error submitting job to chimpd: #{error_message}, retrying..."
        attempts -= 1
        sleep 5 and retry if attempts > 0
        return false

      rescue Errno::ECONNRESET => ex
        $stderr.puts "WARNING: Connection reset by peer, retrying..."
        attempts -= 1
        sleep 5 and retry if attempts > 0
        return false

      rescue Errno::EPIPE => ex
        $stderr.puts "WARNING: broken pipe, retrying..."
        attempts -= 1
        sleep 5 and retry if attempts > 0
        return false

      rescue Errno::ECONNREFUSED => ex
        $stderr.puts "ERROR: connection refused, aborting"
        return false

      rescue RestClient::Exception => ex
        $stderr.puts "ERROR: Error submitting job to chimpd #{chimp_object.script}: #{ex.message}"
        return false
      end
    end

    #
    # quit a remote chimpd
    #
    def self.quit(host, port)
      response = RestClient.post "http://#{host}:#{port}/admin", { 'shutdown' => 'true' }.to_yaml
      return response.code
    end

    #
    # retrieve job info from a remote chimpd
    #
    def self.retrieve_job_info(host, port)
      uri = "http://#{host}:#{port}/job/0"
      response = RestClient.get uri
      jobs = YAML::load(response.body)
      return jobs
    end

    def self.retrieve_group_info(host, port, group_name, status)
      uri = "http://#{host}:#{port}/group/#{group_name}/#{status}"
      response = RestClient.get uri
      group = YAML::load(response.body)
      return group
    end

    def self.set_job_status(host, port, job_id, status)
      uri = "http://#{host}:#{port}/job/#{job_id}/update"
      response = RestClient.post uri, { :status => status}
      return YAML::load(response.body)
    end

    def self.create_group(host, port, name, type, concurrency)
      uri = "http://#{host}:#{port}/group/#{name}/create"
      payload = { 'type' => type, 'concurrency' => concurrency }.to_yaml
      response = RestClient.post(uri, payload)
      return YAML::load(response.body)
    end

    def self.retry_group(host, port, group_name)
      uri = "http://#{host}:#{port}/group/#{group_name}/retry"
      response = RestClient.post(uri, {})
      return YAML::load(response.body)
    end

  end
end
