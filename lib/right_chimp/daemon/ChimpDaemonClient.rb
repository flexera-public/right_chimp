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
      response = RestClient.post uri, chimp_object.to_yaml
      
      if response.code > 199 and response.code < 300
        begin
          id = YAML::load(response.body)['id']
        rescue StandardError => ex
          puts ex
        end
      else
        $stderr.puts "error submitting to chimpd! response code: #{reponse.code}"
        return false
      end
      
      puts "chimpd submission complete"
      return true
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