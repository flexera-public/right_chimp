#
# Extra classes needed to operate with Chimp
#
module Chimp
  #
  # This task contains parameters that describe a script/task to be executed
  #
  class Executable
    attr_accessor :params, :delay

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
        @delay = 0
    end

    def href
      @params['right_script']['href']
    end
    def name
      @params['right_script']['name']
    end
  end
end
