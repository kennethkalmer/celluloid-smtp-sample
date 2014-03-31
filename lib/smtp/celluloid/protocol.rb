module SMTP
  module Celluloid
    class Protocol

      HeloRegex = /\AHELO\s*/i
      EhloRegex = /\AEHLO\s*/i
      QuitRegex = /\AQUIT/i
      MailFromRegex = /\AMAIL FROM:\s*/i
      RcptToRegex = /\ARCPT TO:\s*/i
      DataRegex = /\ADATA/i
      NoopRegex = /\ANOOP/i
      RsetRegex = /\ARSET/i
      VrfyRegex = /\AVRFY\s+/i
      ExpnRegex = /\AEXPN\s+/i
      HelpRegex = /\AHELP/i
      StarttlsRegex = /\ASTARTTLS/i
      AuthRegex = /\AAUTH\s+/i

      attr_reader :connection

      def initialize( connection )
        @connection = connection

        # Plumbing
        @delimiter  = "\n"
        @linebuffer = []

        init_protocol_state

        # STMP speaks first
        send_greeting

        # Now process
        while data = @connection.readpartial( 4096 ) do
          receive_data data
        end
      end

      def send_greeting
        send_data "220 #{connection.server_greeting}\r\n"
      end

      def receive_data( data )
        return unless (data and data.length > 0)

        if ix = data.index( @delimiter )
          @linebuffer << data[0...ix]
          ln = @linebuffer.join
          @linebuffer.clear
          ln.chomp!
          receive_line ln
          receive_data data[(ix+@delimiter.length)..-1]
        else
          @linebuffer << data
        end
      end

      def receive_line( ln )
        return process_data_line(ln) if @state.include?(:data)
        return process_auth_line(ln) if @state.include?(:auth_incomplete)

        case ln
        when EhloRegex
          process_ehlo $'.dup
        when HeloRegex
          process_helo $'.dup
        when MailFromRegex
          process_mail_from $'.dup
        when RcptToRegex
          process_rcpt_to $'.dup
        when DataRegex
          process_data
        when RsetRegex
          process_rset
        when VrfyRegex
          process_vrfy
        when ExpnRegex
          process_expn
        when HelpRegex
          process_help
        when NoopRegex
          process_noop
        when QuitRegex
          process_quit
        when StarttlsRegex
          process_starttls
        when AuthRegex
          process_auth $'.dup
        else
          process_unknown
        end
      end

      # TODO - implement this properly, the implementation is a stub!
      def process_vrfy
        send_data "250 Ok, but unimplemented\r\n"
      end
      # TODO - implement this properly, the implementation is a stub!
      def process_help
        send_data "250 Ok, but unimplemented\r\n"
      end
      # TODO - implement this properly, the implementation is a stub!
      def process_expn
        send_data "250 Ok, but unimplemented\r\n"
      end

      # EHLO/HELO is always legal, per the standard. On success
      # it always clears buffers and initiates a mail "transaction."
      # Which means that a MAIL FROM must follow.
      #
      # Per the standard, an EHLO/HELO or a RSET "initiates" an email
      # transaction. Thereafter, MAIL FROM must be received before
      # RCPT TO, before DATA. Not sure what this specific ordering
      # achieves semantically, but it does make it easier to
      # implement. We also support user-specified requirements for
      # STARTTLS and AUTH. We make it impossible to proceed to MAIL FROM
      # without fulfilling tls and/or auth, if the user specified either
      # or both as required. We need to check the extension standard
      # for auth to see if a credential is discarded after a RSET along
      # with all the rest of the state. We'll behave as if it is.
      # Now clearly, we can't discard tls after its been negotiated
      # without dropping the connection, so that flag doesn't get cleared.
      #
      def process_ehlo domain
        if connection.receive_ehlo_domain domain
          send_data "250-#{connection.server_domain}\r\n"
          #if @@parms[:starttls]
          #  send_data "250-STARTTLS\r\n"
          #end
          #if @@parms[:auth]
          #  send_data "250-AUTH PLAIN\r\n"
          #end
          send_data "250-NO-SOLICITING\r\n"
          # TODO, size needs to be configurable.
          send_data "250 SIZE 20000000\r\n"
          reset_protocol_state
          @state << :ehlo
        else
          send_data "550 Requested action not taken\r\n"
        end
      end

      def process_helo domain
        if connection.receive_ehlo_domain domain.dup
          send_data "250 #{get_server_domain}\r\n"
          reset_protocol_state
          @state << :ehlo
        else
          send_data "550 Requested action not taken\r\n"
        end
      end

      def process_quit
        send_data "221 Ok\r\n"
        connection.close
      end

      def process_noop
        send_data "250 Ok\r\n"
      end

      def process_unknown
        send_data "500 Unknown command\r\n"
      end

      # So far, only AUTH PLAIN is supported but we should do at least LOGIN as well.
      # TODO, support clients that send AUTH PLAIN with no parameter, expecting a 3xx
      # response and a continuation of the auth conversation.
      #
      def process_auth str
        if @state.include?(:auth)
          send_data "503 auth already issued\r\n"
        elsif str =~ /\APLAIN\s?/i
          if $'.length == 0
            # we got a partial response, so let the client know to send the rest
            @state << :auth_incomplete
            send_data("334 \r\n")
          else
            # we got the initial response, so go ahead & process it
            process_auth_line($')
          end
          #elsif str =~ /\ALOGIN\s+/i
        else
          send_data "504 auth mechanism not available\r\n"
        end
      end

      def process_auth_line(line)
        plain = line.unpack("m").first
        _,user,psw = plain.split("\000")
        if connection.receive_plain_auth user,psw
          send_data "235 authentication ok\r\n"
          @state << :auth
        else
          send_data "535 invalid authentication\r\n"
        end
        @state.delete :auth_incomplete
      end

      # Unusually, we can deal with a Deferrable returned from the user application.
      # This was added to deal with a special case in a particular application, but
      # it would be a nice idea to add it to the other user-code callbacks.
      #
      def process_data
        unless @state.include?(:rcpt)
          send_data "503 Operation sequence error\r\n"
        else
          succeeded = proc {
            send_data "354 Send it\r\n"
            @state << :data
            @databuffer = []
          }
          failed = proc {
            send_data "550 Operation failed\r\n"
          }

          d = connection.receive_data_command

          if d.respond_to?(:callback)
            d.callback(&succeeded)
            d.errback(&failed)
          else
            (d ? succeeded : failed).call
          end
        end
      end

      def process_rset
        reset_protocol_state
        connection.receive_reset
        send_data "250 Ok\r\n"
      end

      def unbind
        connection_ended
      end

      # STARTTLS may not be issued before EHLO, or unless the user has chosen
      # to support it.
      # TODO, must support user-supplied certificates.
      #
      def process_starttls
        if @@parms[:starttls]
          if @state.include?(:starttls)
            send_data "503 TLS Already negotiated\r\n"
          elsif ! @state.include?(:ehlo)
            send_data "503 EHLO required before STARTTLS\r\n"
          else
            send_data "220 Start TLS negotiation\r\n"
            start_tls
            @state << :starttls
          end
        else
          process_unknown
        end
      end


      # Requiring TLS is touchy, cf RFC2784.
      # Requiring AUTH seems to be much more reasonable.
      # We don't currently support any notion of deriving an authentication from the TLS
      # negotiation, although that would certainly be reasonable.
      # We DON'T allow MAIL FROM to be given twice.
      # We DON'T enforce all the various rules for validating the sender or
      # the reverse-path (like whether it should be null), and notifying the reverse
      # path in case of delivery problems. All of that is left to the calling application.
      #
      def process_mail_from sender
        # if (@@parms[:starttls]==:required and !@state.include?(:starttls))
        #   send_data "550 This server requires STARTTLS before MAIL FROM\r\n"
        # elsif (@@parms[:auth]==:required and !@state.include?(:auth))
        #   send_data "550 This server requires authentication before MAIL FROM\r\n"
        if @state.include?(:mail_from)
          send_data "503 MAIL already given\r\n"
        else
          unless connection.receive_sender sender
            send_data "550 sender is unacceptable\r\n"
          else
            send_data "250 Ok\r\n"
            @state << :mail_from
          end
        end
      end

      # Since we require :mail_from to have been seen before we process RCPT TO,
      # we don't need to repeat the tests for TLS and AUTH.
      # Note that we don't remember or do anything else with the recipients.
      # All of that is on the user code.
      # TODO: we should enforce user-definable limits on the total number of
      # recipients per transaction.
      # We might want to make sure that a given recipient is only seen once, but
      # for now we'll let that be the user's problem.
      #
      # User-written code can return a deferrable from receive_recipient.
      #
      def process_rcpt_to rcpt
        unless @state.include?(:mail_from)
          send_data "503 MAIL is required before RCPT\r\n"
        else
          succeeded = proc {
            send_data "250 Ok\r\n"
            @state << :rcpt unless @state.include?(:rcpt)
          }
          failed = proc {
            send_data "550 recipient is unacceptable\r\n"
          }

          d = connection.receive_recipient rcpt

          if d.respond_to?(:set_deferred_status)
            d.callback(&succeeded)
            d.errback(&failed)
          else
            (d ? succeeded : failed).call
          end

=begin
        unless connection.receive_recipient rcpt
          send_data "550 recipient is unacceptable\r\n"
        else
          send_data "250 Ok\r\n"
          @state << :rcpt unless @state.include?(:rcpt)
        end
=end
        end
      end


      # Send the incoming data to the application one chunk at a time, rather than
      # one line at a time. That lets the application be a little more flexible about
      # storing to disk, etc.
      # Since we clear the chunk array every time we submit it, the caller needs to be
      # aware to do things like dup it if he wants to keep it around across calls.
      #
      # Resets the transaction upon disposition of the incoming message.
      # RFC5321 says this about the MAIL FROM command:
      #  "This command tells the SMTP-receiver that a new mail transaction is
      #   starting and to reset all its state tables and buffers, including any
      #   recipients or mail data."
      #
      # Equivalent behaviour is implemented by resetting after a completed transaction.
      #
      # User-written code can return a Deferrable as a response from receive_message.
      #
      def process_data_line ln
        if ln == "."
          if @databuffer.length > 0
            connection.receive_data_chunk @databuffer
            @databuffer.clear
          end


          succeeded = proc {
            send_data "250 Message accepted\r\n"
            reset_protocol_state
          }
          failed = proc {
            send_data "550 Message rejected\r\n"
            reset_protocol_state
          }
          d = connection.receive_message

          if d.respond_to?(:set_deferred_status)
            d.callback(&succeeded)
            d.errback(&failed)
          else
            (d ? succeeded : failed).call
          end

          @state.delete :data
        else
          # slice off leading . if any
          ln.slice!(0...1) if ln[0] == ?.
          @databuffer << ln
          if @databuffer.length > 4096
            connection.receive_data_chunk @databuffer
            @databuffer.clear
          end
        end
      end

      private

      def send_data( data )
        @connection.write data
      end

      # This is called at several points to restore the protocol state
      # to a pre-transaction state. In essence, we "forget" having seen
      # any valid command except EHLO and STARTTLS.
      # We also have to callback user code, in case they're keeping track
      # of senders, recipients, and whatnot.
      #
      # We try to follow the convention of avoiding the verb "receive" for
      # internal method names except receive_line (which we inherit), and
      # using only receive_xxx for user-overridable stubs.
      #
      # init_protocol_state is called when we initialize the connection as
      # well as during reset_protocol_state. It does NOT call the user
      # override method. This enables us to promise the users that they
      # won't see the overridable fire except after EHLO and RSET, and
      # after a message has been received. Although the latter may be wrong.
      # The standard may allow multiple DATA segments with the same set of
      # senders and recipients.
      #
      def reset_protocol_state
        init_protocol_state
        s,@state = @state,[]
        @state << :starttls if s.include?(:starttls)
        @state << :ehlo if s.include?(:ehlo)
      end
      def init_protocol_state
        @state ||= []
      end

    end
  end
end
