# this is the class for selection errorclass
class InvalidSelectionError < StandardError
  def initialize(msg = 'The criteria for selection was invalid')
    super
  end
end
