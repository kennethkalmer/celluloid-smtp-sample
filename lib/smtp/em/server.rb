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

      # The greeting returned in the initial connection message to the client.
      def server_greeting
        "EventMachine SMTP Server"
      end
      # The domain name returned in the first line of the response to a
      # successful EHLO or HELO command.
      def server_domain
        "Ok EventMachine SMTP Server"
      end

      # A false response from this user-overridable method will cause a
      # 550 error to be returned to the remote client.
      #
      def receive_ehlo_domain domain
        true
      end

      # Return true or false to indicate that the authentication is acceptable.
      def receive_plain_auth user, password
        true
      end

      # Receives the argument of the MAIL FROM command. Return false to
      # indicate to the remote client that the sender is not accepted.
      # This can only be successfully called once per transaction.
      #
      def receive_sender sender
        true
      end

      # Receives the argument of a RCPT TO command. Can be given multiple
      # times per transaction. Return false to reject the recipient.
      #
      def receive_recipient rcpt
        true
      end

      # Sent when the remote peer issues the RSET command.
      # Since RSET is not allowed to fail (according to the protocol),
      # we ignore any return value from user overrides of this method.
      #
      def receive_reset
      end

      # Sent when the remote peer has ended the connection.
      #
      def connection_ended
      end

      # Called when the remote peer sends the DATA command.
      # Returning false will cause us to send a 550 error to the peer.
      # This can be useful for dealing with problems that arise from processing
      # the whole set of sender and recipients.
      #
      def receive_data_command
        true
      end

      # Sent when data from the remote peer is available. The size can be controlled
      # by setting the :chunksize parameter. This call can be made multiple times.
      # The goal is to strike a balance between sending the data to the application one
      # line at a time, and holding all of a very large message in memory.
      #
      def receive_data_chunk data
        #@smtps_msg_size ||= 0
        #@smtps_msg_size += data.join.length
        #STDERR.write "<#{@smtps_msg_size}>"
      end

      # Sent after a message has been completely received. User code
      # must return true or false to indicate whether the message has
      # been accepted for delivery.
      def receive_message
        #$>.puts "Received complete message"
        true
      end

      # This is called when the protocol state is reset. It happens
      # when the remote client calls EHLO/HELO or RSET.
      def receive_transaction
      end

    end
  end
end
