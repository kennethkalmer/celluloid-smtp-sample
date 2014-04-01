require 'celluloid/io'

require 'smtp/celluloid/connection'

module SMTP
  module Celluloid
    class Server
      include ::Celluloid::IO
      finalizer :finalize

      def self.start!( host, port )
        supervisor = self.supervise( host, port )
        trap("INT") { supervisor.terminate; exit }

        loop do
          sleep 5 while supervisor.alive?
        end
      end

      def initialize( host, port )
        # Since we're including Celluloid::IO, we're actually making a
        # Celluloid::IO::TCPServer here
        @server = TCPServer.new( host, port )
        @server.setsockopt(Socket::IPPROTO_TCP, :TCP_NODELAY, 1)

        async.run
      end

      def finalize
        @server.close if @server
      end

      def run
        loop { async.handle_connection @server.accept }
      end

      def handle_connection( socket )
        _, port, host = socket.peeraddr
        puts "*** Received connection from #{host}:#{port}"

        connection = Connection.new( socket )
      rescue EOFError
        socket.close
      end

    end
  end
end
