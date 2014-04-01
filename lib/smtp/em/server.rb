require 'eventmachine'

module SMTP
  module EM
    class Server < EventMachine::Protocols::SmtpServer

      def self.start!( host, port )
        EventMachine.run {
          EventMachine.error_handler { |e|
            p [ :exception_in_reactor, e.message, e.backtrace ]
          }

          EventMachine.start_server( host, port, self )
        }
      end

      def receive_data_chunk( data )
      end

    end
  end
end
