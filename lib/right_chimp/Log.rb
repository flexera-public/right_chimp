module Chimp
  class Log
    @@logger = Logger.new(STDOUT)
    @@logger.sev_threshold=Logger::INFO
    
    def self.logger=(l)
      @@logger = l
    end

    def self.threshold=(level)
      @@logger.sev_threshold=level
    end

    def self.default_level(level)
      @@logger.level = level
    end

    def self.debug(m)
      @@logger.debug(m)
    end
    
    def self.info(m)
      @@logger.info(m)
    end

    def self.warn(m)
      @@logger.warn(m)
    end
    
    def self.error(m)
      @@logger.error(m)
    end    
  end
end
