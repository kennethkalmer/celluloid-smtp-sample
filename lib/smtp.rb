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
    supervisor = server.supervise( host, port )
    trap("INT") { supervisor.terminate; exit }

    loop do
      sleep 5 while supervisor.alive?
    end
  end

end
