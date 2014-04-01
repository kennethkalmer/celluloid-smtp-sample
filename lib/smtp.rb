$:.unshift File.expand_path('../', __FILE__)

module SMTP

  extend self

  def host
    ENV['HOST'] || 'localhost'
  end

  def port
    ENV['PORT'] || 1025
  end

  def start!( server )
    server.start! host, port
  end

end
