#
# Report
#
# :fields is a comma seperated list of fields to report on,
#
# Example: ip-address,name,href,private-ip-address,resource_uid,
# ec2-instance-type,datacenter,dns-name,locked,tag=foo
module Chimp
  class ExecReport < Executor
    attr_reader :server, :fields
    attr_writer :server, :fields

    def info
      return "report on server #{fields.inspect}"
    end

    def run
      run_with_retry do
        output = []

        begin
          s=@server
          Log.debug "Making API 1.5 call: client.tags"
          response=Connection.client.tags.by_resource(:resource_hrefs => [@server.href]).first.tags
        rescue Exception => ex
          raise e
          s = @server
          response = nil
        end

        s.params["tags"] = [] unless s.params["tags"]
        response.each do |t|
          s.params["tags"] += [ t['name'] ]
        end

        @fields.split(",").each do |f|
          if f =~ /^tag=([^,]+)/
            tag_search_string = $1
            s.params["tags"].each do |tag|
              output << tag if tag =~ /^#{tag_search_string}/
            end
          else
            output << s.params[f]
          end
        end

        puts output.join(",")
      end
    end
  end
end
