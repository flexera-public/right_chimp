require 'rubygems'
require 'bundler'

require 'getoptlong'
require 'thread'
require 'webrick'
require 'singleton'
require 'base64'
require 'rake'

require 'progressbar'
require 'json'
require 'yaml'
require 'highline/import'

require 'right_api_client'
require 'rest-client'
require 'logger'

require 'pry'

# Group all the requires for Chimp
module Chimp
  require 'right_chimp/version'
  require 'right_chimp/chimp'
  require 'right_chimp/log'
  require 'right_chimp/id_manager'

  require 'right_chimp/daemon/chimp_daemon'
  require 'right_chimp/daemon/chimp_daemon_client'

  require 'right_chimp/queue/chimp_queue'
  require 'right_chimp/queue/queue_worker'
  require 'right_chimp/queue/execution_group'

  require 'right_chimp/exec/executor'
  require 'right_chimp/exec/exec_array'
  require 'right_chimp/exec/exec_rightscript'
  require 'right_chimp/exec/exec_ssh'
  require 'right_chimp/exec/exec_report'
  require 'right_chimp/exec/exec_noop'

  require 'right_chimp/resources/connection'
  require 'right_chimp/resources/executable'
  require 'right_chimp/resources/server'
  require 'right_chimp/resources/task'
end
