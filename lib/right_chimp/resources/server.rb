#
# Extra classes needed to operate with Chimp
#
module Chimp
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
      Log.debug "[#{Chimp.get_job_uuid}] Running executable"
      task = self.object.run_executable(script_href + params)
      return task
    end
  end
end
