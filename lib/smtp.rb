$:.unshift File.expand_path('../', __FILE__)

module SMTP

  extend self

  def host
    ENV['HOST'] || '127.0.0.1'
  end

  def port
    ENV['PORT'] || 1025
  end

  def start!( server )
    server.start! host, port
  end

end
