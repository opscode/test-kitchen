# -*- encoding: utf-8 -*-
#
# Author:: Salim Afiune (<salim@afiunemaya.com.mx>)
# Author:: Matt Wrock (<matt@mattwrock.com>)
# Author:: Fletcher Nichol (<fnichol@nichol.ca>)
#
# Copyright (C) 2014, Salim Afiune
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "rbconfig"
require "uri"

require "kitchen"

module Kitchen
  module Transport
    # Wrapped exception for any internally raised WinRM-related errors.
    #
    # @author Fletcher Nichol <fnichol@nichol.ca>
    class WinrmFailed < TransportFailed; end

    # A Transport which uses WinRM to execute commands and transfer files.
    #
    # @author Matt Wrock <matt@mattwrock.com>
    # @author Salim Afiune <salim@afiunemaya.com.mx>
    # @author Fletcher Nichol <fnichol@nichol.ca>
    class Winrm < Kitchen::Transport::Base
      kitchen_transport_api_version 1

      plugin_version Kitchen::VERSION

      default_config :username, "administrator"
      default_config :password, nil
      default_config :rdp_port, 3389
      default_config :connection_retries, 5
      default_config :connection_retry_sleep, 1
      default_config :max_wait_until_ready, 600
      default_config :winrm_transport, "plaintext"
      default_config :port do |transport|
        transport[:winrm_transport] == :ssl ? 5986 : 5985
      end
      default_config :endpoint_template do |transport|
        scheme = transport[:winrm_transport] == :ssl ? "https" : "http"
        "#{scheme}://%{hostname}:%{port}/wsman"
      end

      def finalize_config!(instance)
        super

        transport = config[:winrm_transport].to_sym
        config[:winrm_transport] =
         case transport
         when :sspinegotiate
           if host_os_windows?
             transport
           else
             :plaintext
           end
         else
           transport
         end

        self
      end

      # (see Base#connection)
      def connection(state, &block)
        options = connection_options(config.to_hash.merge(state))

        if @connection && @connection_options == options
          reuse_connection(&block)
        else
          create_new_connection(options, &block)
        end
      end

      # A Connection instance can be generated and re-generated, given new
      # connection details such as connection port, hostname, credentials, etc.
      # This object is responsible for carrying out the actions on the remote
      # host such as executing commands, transferring files, etc.
      #
      # @author Fletcher Nichol <fnichol@nichol.ca>
      class Connection < Kitchen::Transport::Base::Connection
        # (see Base::Connection#close)
        def close
          return if @session.nil?

          shell_id = session.shell
          logger.debug("[WinRM] closing remote shell #{shell_id} on #{self}")
          session.close
          logger.debug("[WinRM] remote shell #{shell_id} closed")
        ensure
          @session = nil
        end

        # (see Base::Connection#execute)
        def execute(command)
          return if command.nil?
          logger.debug("[WinRM] #{self} (#{command})")

          if command.length > MAX_COMMAND_SIZE
            command = run_from_file_command(command)
          end
          exit_code, stderr = execute_with_exit_code(command)

          if logger.debug? && exit_code == 0
            log_stderr_on_warn(stderr)
          elsif exit_code != 0
            log_stderr_on_warn(stderr)
            raise Transport::WinrmFailed,
              "WinRM exited (#{exit_code}) for command: [#{command}]"
          end
        end

        # (see Base::Connection#login_command)
        def login_command
          case RbConfig::CONFIG["host_os"]
          when /darwin/
            login_command_for_mac
          when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
            login_command_for_windows
          when /linux/
            login_command_for_linux
          else
            fail ActionFailed, "Remote login not supported in #{self.class} " \
              "from host OS '#{RbConfig::CONFIG["host_os"]}'."
          end
        end

        # (see Base::Connection#upload)
        def upload(locals, remote)
          file_transporter.upload(locals, remote)
        end

        # (see Base::Connection#wait_until_ready)
        def wait_until_ready
          delay = 3
          session(
            :retries => max_wait_until_ready / delay,
            :delay => delay,
            :message => "Waiting for WinRM service on #{endpoint}, " \
              "retrying in #{delay} seconds"
          )
          execute(PING_COMMAND.dup)
        end

        private

        PING_COMMAND = "Write-Host '[WinRM] Established\n'".freeze

        # Maximum string to send to the transport to execute. WinRM has an 8000 character
        # command line limit. The original command string is coverted to a base 64 encoded
        # UTF-16 string which will double the string size.
        MAX_COMMAND_SIZE = 3000

        RESCUE_EXCEPTIONS_ON_ESTABLISH = lambda do
          [
            Errno::EACCES, Errno::EADDRINUSE, Errno::ECONNREFUSED, Errno::ETIMEDOUT,
            Errno::ECONNRESET, Errno::ENETUNREACH, Errno::EHOSTUNREACH,
            ::WinRM::WinRMHTTPTransportError, ::WinRM::WinRMAuthorizationError,
            HTTPClient::KeepAliveDisconnected,
            HTTPClient::ConnectTimeoutError
          ].freeze
        end

        # @return [Integer] how many times to retry when failing to execute
        #   a command or transfer files
        # @api private
        attr_reader :connection_retries

        # @return [Float] how many seconds to wait before attempting a retry
        #   when failing to execute a command or transfer files
        # @api private
        attr_reader :connection_retry_sleep

        # @return [String] the endpoint URL of the remote WinRM host
        # @api private
        attr_reader :endpoint

        # @return [String] display name for the associated instance
        # @api private
        attr_reader :instance_name

        # @return [String] local path to the root of the project
        # @api private
        attr_reader :kitchen_root

        # @return [Integer] how many times to retry when invoking
        #   `#wait_until_ready` before failing
        # @api private
        attr_reader :max_wait_until_ready

        # @return [Integer] the TCP port number to use when connection to the
        #   remote WinRM host
        # @api private
        attr_reader :rdp_port

        # @return [Symbol] the transport strategy to use when constructing a
        #   `WinRM::WinRMWebService`
        # @api private
        attr_reader :winrm_transport

        # Writes an RDP document to the local file system.
        #
        # @param opts [Hash] file options
        # @option opts [true,false] :mac whether or not the document is for a
        #   Mac system
        # @api private
        def create_rdp_doc(opts = {})
          content = Util.outdent!(<<-RDP)
            full address:s:#{URI.parse(endpoint).host}:#{rdp_port}
            prompt for credentials:i:1
            username:s:#{options[:user]}
          RDP
          content.prepend("drivestoredirect:s:*\n") if opts[:mac]

          File.open(rdp_doc_path, "wb") { |f| f.write(content) }

          if logger.debug?
            debug("Creating RDP document for #{instance_name} (#{rdp_doc_path})")
            debug("------------")
            IO.read(rdp_doc_path).each_line { |l| debug("#{l.chomp}") }
            debug("------------")
          end
        end

        # Establish a remote shell session on the remote host.
        #
        # @param opts [Hash] retry options
        # @option opts [Integer] :retries the number of times to retry before
        #   failing
        # @option opts [Float] :delay the number of seconds to wait until
        #   attempting a retry
        # @option opts [String] :message an optional message to be logged on
        #   debug (overriding the default) when a rescuable exception is raised
        # @return [Winrm::CommandExecutor] the command executor session
        # @api private
        def establish_shell(opts)
          service_args = [endpoint, winrm_transport, options]
          @service = ::WinRM::WinRMWebService.new(*service_args)
          closer = WinRM::Transport::ShellCloser.new("#{self}", logger.debug?, service_args)

          executor = WinRM::Transport::CommandExecutor.new(@service, logger, closer)
          retryable(opts) do
            logger.debug("[WinRM] opening remote shell on #{self}")
            shell_id = executor.open
            logger.debug("[WinRM] remote shell #{shell_id} is open on #{self}")
          end
          executor
        end

        # Execute a Powershell script over WinRM and return the command's
        # exit code and standard error.
        #
        # @param command [String] Powershell script to execute
        # @return [[Integer,String]] an array containing the exit code of the
        #   script and the standard error stream
        # @api private
        def execute_with_exit_code(command)
          response = session.run_powershell_script(command) do |stdout, _|
            logger << stdout if stdout
          end

          [response[:exitcode], response.stderr]
        end

        # @return [Winrm::FileTransporter] a file transporter
        # @api private
        def file_transporter
          @file_transporter ||= WinRM::Transport::FileTransporter.new(session, logger)
        end

        # (see Base#init_options)
        def init_options(options)
          super
          @instance_name      = @options.delete(:instance_name)
          @kitchen_root       = @options.delete(:kitchen_root)
          @endpoint           = @options.delete(:endpoint)
          @rdp_port           = @options.delete(:rdp_port)
          @winrm_transport    = @options.delete(:winrm_transport)
          @connection_retries = @options.delete(:connection_retries)
          @connection_retry_sleep = @options.delete(:connection_retry_sleep)
          @max_wait_until_ready   = @options.delete(:max_wait_until_ready)
        end

        # Logs formatted standard error output at the warning level.
        #
        # @param stderr [String] standard error output
        # @api private
        def log_stderr_on_warn(stderr)
          error_regexp = /<S S=\"Error\">/

          if error_regexp.match(stderr)
            stderr.
              split(error_regexp)[1..-2].
              map! { |line| line.sub(/_x000D__x000A_<\/S>/, "").rstrip }.
              each { |line| logger.warn(line) }
          else
            stderr.
              split("\r\n").
              each { |line| logger.warn(line) }
          end
        end

        # Builds a `LoginCommand` for use by Linux-based platforms.
        #
        # TODO: determine whether or not `desktop` exists
        #
        # @return [LoginCommand] a login command
        # @api private
        def login_command_for_linux
          args  = %W[-u #{options[:user]}]
          args += %W[-p #{options[:pass]}] if options.key?(:pass)
          args += %W[#{URI.parse(endpoint).host}:#{rdp_port}]

          LoginCommand.new("rdesktop", args)
        end

        # Builds a `LoginCommand` for use by Mac-based platforms.
        #
        # @return [LoginCommand] a login command
        # @api private
        def login_command_for_mac
          create_rdp_doc(:mac => true)

          LoginCommand.new("open", rdp_doc_path)
        end

        # Builds a `LoginCommand` for use by Windows-based platforms.
        #
        # @return [LoginCommand] a login command
        # @api private
        def login_command_for_windows
          create_rdp_doc

          LoginCommand.new("mstsc", rdp_doc_path)
        end

        # @return [String] path to the local RDP document
        # @api private
        def rdp_doc_path
          File.join(kitchen_root, ".kitchen", "#{instance_name}.rdp")
        end

        # Yields to a block and reties the block if certain rescuable
        # exceptions are raised.
        #
        # @param opts [Hash] retry options
        # @option opts [Integer] :retries the number of times to retry before
        #   failing
        # @option opts [Float] :delay the number of seconds to wait until
        #   attempting a retry
        # @option opts [String] :message an optional message to be logged on
        #   debug (overriding the default) when a rescuable exception is raised
        # @return [Winrm::CommandExecutor] the command executor session
        # @api private
        def retryable(opts)
          yield
        rescue *RESCUE_EXCEPTIONS_ON_ESTABLISH.call => e
          if (opts[:retries] -= 1) > 0
            message = if opts[:message]
              logger.debug("[WinRM] connection failed (#{e.inspect})")
              opts[:message]
            else
              "[WinRM] connection failed, " \
                "retrying in #{opts[:delay]} seconds (#{e.inspect})"
            end
            logger.info(message)
            sleep(opts[:delay])
            retry
          else
            logger.warn("[WinRM] connection failed, terminating (#{e.inspect})")
            raise
          end
        end

        # Establishes a remote shell session, or establishes one when invoked
        # the first time.
        #
        # @param retry_options [Hash] retry options for the initial connection
        # @return [Winrm::CommandExecutor] the command executor session
        # @api private
        def session(retry_options = {})
          @session ||= establish_shell({
            :retries => connection_retries.to_i,
            :delay => connection_retry_sleep.to_i
          }.merge(retry_options))
        end

        # String representation of object, reporting its connection details and
        # configuration.
        #
        # @api private
        def to_s
          "#{winrm_transport}::#{endpoint}<#{options.inspect}>"
        end

        # takes a long (greater than 3000 characters) command and saves it to a
        # file and uploads it to the test instance.
        #
        # @param command [String] a long command to be saved and uploaded
        # @return [String] a command that executes the uploaded script
        # @api private
        def run_from_file_command(command)
          temp_dir = Dir.mktmpdir("kitchen-long-script")
          begin
            script_name = "#{instance_name}-long_script.ps1"
            script_path = File.join(temp_dir, script_name)

            File.open(script_path, "wb") do |file|
              file.write(command)
            end

            target_path = File.join("$env:TEMP", "kitchen")
            upload(script_path, target_path)

            %{& "#{File.join(target_path, script_name)}"}
          ensure
            FileUtils.rmtree(temp_dir)
          end
        end
      end

      private

      WINRM_TRANSPORT_SPEC_VERSION = ["~> 1.0", ">= 1.0.3"].freeze

      # Builds the hash of options needed by the Connection object on
      # construction.
      #
      # @param data [Hash] merged configuration and mutable state data
      # @return [Hash] hash of connection options
      # @api private
      def connection_options(data)
        opts = {
          :instance_name => instance.name,
          :kitchen_root => data[:kitchen_root],
          :logger => logger,
          :endpoint => data[:endpoint_template] % data,
          :user => data[:username],
          :pass => data[:password],
          :rdp_port => data[:rdp_port],
          :connection_retries => data[:connection_retries],
          :connection_retry_sleep => data[:connection_retry_sleep],
          :max_wait_until_ready => data[:max_wait_until_ready],
          :winrm_transport => data[:winrm_transport]
        }
        opts.merge!(additional_transport_args(opts[:winrm_transport]))
        opts
      end

      def additional_transport_args(transport_type)
        case transport_type
        when :ssl, :sspinegotiate
          {
            :no_ssl_peer_verification => true,
            :disable_sspi => false,
            :basic_auth_only => false
          }
        when :plaintext
          {
            :disable_sspi => true,
            :basic_auth_only => true
          }
        end
      end

      # Creates a new WinRM Connection instance and save it for potential
      # future reuse.
      #
      # @param options [Hash] conneciton options
      # @return [Ssh::Connection] a WinRM Connection instance
      # @api private
      def create_new_connection(options, &block)
        if @connection
          logger.debug("[WinRM] shutting previous connection #{@connection}")
          @connection.close
        end

        @connection_options = options
        @connection = Kitchen::Transport::Winrm::Connection.new(options, &block)
      end

      # (see Base#load_needed_dependencies!)
      def load_needed_dependencies!
        super
        load_winrm_transport!
        load_winrm_s! if host_os_windows?
      end

      # Load WinRM::Transport code.
      #
      # @api private
      def load_winrm_transport!
        spec_version = WINRM_TRANSPORT_SPEC_VERSION.dup
        options = {
          :load_msg => "Winrm Transport requested," \
          " loading WinRM::Transport gem (#{spec_version})",
          :success_msg => "WinRM::Transport library loaded",
          :already_msg => "WinRM::Transport previously loaded",
          :name => "winrm-transport",
          :version => spec_version
        }

        load_with_rescue!(options) do
          gem "winrm-transport", WINRM_TRANSPORT_SPEC_VERSION.dup
          require "winrm/transport/version"
        end

        silence_warnings { require "winrm" }
        require "winrm/transport/shell_closer"
        require "winrm/transport/command_executor"
        require "winrm/transport/file_transporter"
      end

      def load_winrm_s!
        options = {
          :load_msg => "The winrm-s gem is being loaded" \
          " to enable sspiauthentication.",
          :success_msg => "winrm-s is loaded." \
            "  sspinegotiate auth is now available.",
          :already_msg => "winrm-s was already loaded.",
          :name => "winrm-s"
        }

        load_with_rescue!(options) { require "winrm-s" }
      end

      def load_with_rescue!(options = {}, &block)
        logger.debug(options[:load_msg])
        attempt_load = execute_block(&block)
        if attempt_load
          logger.debug(options[:success_msg])
        else
          logger.debug(options[:already_msg])
        end
      rescue LoadError => e
        message = fail_to_load_gem_message(options[:name],
          options[:version])
        logger.fatal(message)
        raise UserError,
          "Could not load or activate #{options[:name]}. (#{e.message})"
      end

      def execute_block
        yield if block_given?
      end

      def fail_to_load_gem_message(name, version = nil)
        version_cmd = "--version '#{version}'" if version
        version_file = "', '#{version}"

        "The `#{name}` gem is missing and must" \
          " be installed or cannot be properly activated. Run" \
          " `gem install #{name} #{version_cmd}`" \
          " or add the following to your Gemfile if you are using Bundler:" \
          " `gem '#{name} #{version_file}'`."
      end

      def host_os_windows?
        case RbConfig::CONFIG["host_os"]
        when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
          true
        else
          false
        end
      end

      # Return the last saved WinRM connection instance.
      #
      # @return [Winrm::Connection] a WinRM Connection instance
      # @api private
      def reuse_connection
        logger.debug("[WinRM] reusing existing connection #{@connection}")
        yield @connection if block_given?
        @connection
      end

      def silence_warnings
        old_verbose, $VERBOSE = $VERBOSE, nil
        yield
      ensure
        $VERBOSE = old_verbose
      end
    end
  end
end
