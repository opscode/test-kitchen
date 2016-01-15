# -*- encoding: utf-8 -*-
#
# Author:: Matt Wrock (<matt@mattwrock.com>)
#
# Copyright (C) 2014, Matt Wrock
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

require_relative "../../spec_helper"

require "kitchen/transport/winrm"
require "winrm"
require "winrm/transport/command_executor"
require "winrm/transport/shell_closer"
require "winrm/transport/file_transporter"

module Kitchen

  module Transport

    class WinRMConnectionDummy < Kitchen::Transport::Winrm::Connection

      attr_reader :saved_command, :remote_path, :local_path

      def upload(locals, remote)
        @saved_command = IO.read(locals)
        @local_path = locals
        @remote_path = remote
      end
    end
  end
end

describe Kitchen::Transport::Winrm do

  before do
    RbConfig::CONFIG.stubs(:[]).with("host_os").returns("blah")
  end

  let(:logged_output) { StringIO.new }
  let(:logger)        { Logger.new(logged_output) }
  let(:config)        { Hash.new }
  let(:state)         { Hash.new }

  let(:instance) do
    stub(:name => "coolbeans", :logger => logger, :to_str => "instance")
  end

  let(:transport) do
    t = Kitchen::Transport::Winrm.new(config)
    # :load_winrm_s! is not cross-platform safe
    # and gets initialized too early in the pipeline
    t.stubs(:load_winrm_s!)
    t.finalize_config!(instance)
  end

  it "provisioner api_version is 1" do
    transport.diagnose_plugin[:api_version].must_equal 1
  end

  it "plugin_version is set to Kitchen::VERSION" do
    transport.diagnose_plugin[:version].must_equal Kitchen::VERSION
  end

  describe "default_config" do

    it "sets :port to 5985 by default" do
      transport[:port].must_equal 5985
    end

    it "sets :username to administrator by default" do
      transport[:username].must_equal "administrator"
    end

    it "sets :password to nil by default" do
      transport[:password].must_equal nil
    end

    it "sets a default :endpoint_template value" do
      transport[:endpoint_template].
        must_equal "http://%{hostname}:%{port}/wsman"
    end

    it "sets :rdp_port to 3389 by default" do
      transport[:rdp_port].must_equal 3389
    end

    it "sets :connection_retries to 5 by default" do
      transport[:connection_retries].must_equal 5
    end

    it "sets :connection_retry_sleep to 1 by default" do
      transport[:connection_retry_sleep].must_equal 1
    end

    it "sets :max_wait_until_ready to 600 by default" do
      transport[:max_wait_until_ready].must_equal 600
    end

    it "sets :winrm_transport to :plaintext" do
      transport[:winrm_transport].must_equal :plaintext
    end
  end

  describe "#connection" do

    let(:klass) { Kitchen::Transport::Winrm::Connection }

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    def self.common_connection_specs
      before do
        config[:hostname] = "here"
        config[:kitchen_root] = "/i/am/root"
      end

      it "returns a Kitchen::Transport::Winrm::Connection object" do
        transport.connection(state).must_be_kind_of klass
      end

      it "sets :instance_name to the instance's name" do
        klass.expects(:new).with do |hash|
          hash[:instance_name] == "coolbeans"
        end

        make_connection
      end
      it "sets :kitchen_root to the transport's kitchen_root" do
        klass.expects(:new).with do |hash|
          hash[:kitchen_root] == "/i/am/root"
        end

        make_connection
      end

      it "sets the :logger to the transport's logger" do
        klass.expects(:new).with do |hash|
          hash[:logger] == logger
        end

        make_connection
      end

      it "sets the :winrm_transport to :plaintext" do
        klass.expects(:new).with do |hash|
          hash[:winrm_transport] == :plaintext
        end

        make_connection
      end

      it "sets the :disable_sspi to true" do
        klass.expects(:new).with do |hash|
          hash[:disable_sspi] == true
        end

        make_connection
      end

      it "sets the :basic_auth_only to true" do
        klass.expects(:new).with do |hash|
          hash[:basic_auth_only] == true
        end

        make_connection
      end

      it "sets :endpoint from data in config" do
        config[:hostname] = "host_from_config"
        config[:port] = "port_from_config"
        config[:winrm_transport] = "ssl"

        klass.expects(:new).with do |hash|
          hash[:endpoint] == "https://host_from_config:port_from_config/wsman"
        end

        make_connection
      end

      it "sets :endpoint from data in state over config data" do
        state[:hostname] = "host_from_state"
        config[:hostname] = "host_from_config"
        state[:port] = "port_from_state"
        config[:port] = "port_from_config"
        config[:winrm_transport] = "ssl"

        klass.expects(:new).with do |hash|
          hash[:endpoint] == "https://host_from_state:port_from_state/wsman"
        end

        make_connection
      end

      it "sets :user from :username in config" do
        config[:username] = "user_from_config"

        klass.expects(:new).with do |hash|
          hash[:user] == "user_from_config"
        end

        make_connection
      end

      it "sets :user from :username in state over config data" do
        state[:username] = "user_from_state"
        config[:username] = "user_from_config"

        klass.expects(:new).with do |hash|
          hash[:user] == "user_from_state"
        end

        make_connection
      end

      it "sets :pass from :password in config" do
        config[:password] = "pass_from_config"

        klass.expects(:new).with do |hash|
          hash[:pass] == "pass_from_config"
        end

        make_connection
      end

      it "sets :pass from :password in state over config data" do
        state[:password] = "pass_from_state"
        config[:password] = "pass_from_config"

        klass.expects(:new).with do |hash|
          hash[:pass] == "pass_from_state"
        end

        make_connection
      end

      it "sets :rdp_port from config" do
        config[:rdp_port] = "rdp_from_config"

        klass.expects(:new).with do |hash|
          hash[:rdp_port] == "rdp_from_config"
        end

        make_connection
      end

      it "sets :rdp_port from state over config data" do
        state[:rdp_port] = "rdp_from_state"
        config[:rdp_port] = "rdp_from_config"

        klass.expects(:new).with do |hash|
          hash[:rdp_port] == "rdp_from_state"
        end

        make_connection
      end

      it "sets :connection_retries from config" do
        config[:connection_retries] = "retries_from_config"

        klass.expects(:new).with do |hash|
          hash[:connection_retries] == "retries_from_config"
        end

        make_connection
      end

      it "sets :connection_retries from state over config data" do
        state[:connection_retries] = "retries_from_state"
        config[:connection_retries] = "retries_from_config"

        klass.expects(:new).with do |hash|
          hash[:connection_retries] == "retries_from_state"
        end

        make_connection
      end

      it "sets :connection_retry_sleep from config" do
        config[:connection_retry_sleep] = "sleep_from_config"

        klass.expects(:new).with do |hash|
          hash[:connection_retry_sleep] == "sleep_from_config"
        end

        make_connection
      end

      it "sets :connection_retry_sleep from state over config data" do
        state[:connection_retry_sleep] = "sleep_from_state"
        config[:connection_retry_sleep] = "sleep_from_config"

        klass.expects(:new).with do |hash|
          hash[:connection_retry_sleep] == "sleep_from_state"
        end

        make_connection
      end

      it "sets :max_wait_until_ready from config" do
        config[:max_wait_until_ready] = "max_from_config"

        klass.expects(:new).with do |hash|
          hash[:max_wait_until_ready] == "max_from_config"
        end

        make_connection
      end

      it "sets :max_wait_until_ready from state over config data" do
        state[:max_wait_until_ready] = "max_from_state"
        config[:max_wait_until_ready] = "max_from_config"

        klass.expects(:new).with do |hash|
          hash[:max_wait_until_ready] == "max_from_state"
        end

        make_connection
      end

      it "sets :winrm_transport from config data" do
        config[:winrm_transport] = "ssl"

        klass.expects(:new).with do |hash|
          hash[:winrm_transport] == :ssl
        end

        make_connection
      end

      describe "when sspinegotiate is set in config" do
        before do
          config[:winrm_transport] = "sspinegotiate"
        end

        describe "for Windows workstations" do
          before do
            RbConfig::CONFIG.stubs(:[]).with("host_os").returns("mingw32")
          end

          it "sets :winrm_transport to sspinegotiate on Windows" do

            klass.expects(:new).with do |hash|
              hash[:winrm_transport] == :sspinegotiate &&
                hash[:disable_sspi] == false &&
                hash[:basic_auth_only] == false
            end

            make_connection
          end
        end

        describe "for non-Windows workstations" do
          before do
            RbConfig::CONFIG.stubs(:[]).with("host_os").returns("darwin14")
          end

          it "sets :winrm_transport to plaintext" do
            klass.expects(:new).with do |hash|
              hash[:winrm_transport] == :plaintext &&
                hash[:disable_sspi] == true &&
                hash[:basic_auth_only] == true
            end

            make_connection
          end
        end
      end

      it "returns the same connection when called again with same state" do
        first_connection  = make_connection(state)
        second_connection = make_connection(state)

        first_connection.object_id.must_equal second_connection.object_id
      end

      it "logs a debug message when the connection is reused" do
        make_connection(state)
        make_connection(state)

        logged_output.string.lines.count { |l|
          l =~ debug_line_with("[WinRM] reusing existing connection ")
        }.must_equal 1
      end

      it "returns a new connection when called again if state differs" do
        first_connection  = make_connection(state)
        second_connection = make_connection(state.merge(:port => 9000))

        first_connection.object_id.wont_equal second_connection.object_id
      end

      it "closes first connection when a second is created" do
        first_connection = make_connection(state)
        first_connection.expects(:close)

        make_connection(state.merge(:port => 9000))
      end

      it "logs a debug message a second connection is created" do
        make_connection(state)
        make_connection(state.merge(:port => 9000))

        logged_output.string.lines.count { |l|
          l =~ debug_line_with("[WinRM] shutting previous connection ")
        }.must_equal 1
      end
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

    describe "called without a block" do

      def make_connection(s = state)
        transport.connection(s)
      end

      common_connection_specs
    end

    describe "called with a block" do

      def make_connection(s = state)
        transport.connection(s) do |conn|
          conn
        end
      end

      common_connection_specs
    end
  end

  describe "#load_needed_dependencies" do
    describe "winrm-transport" do
      before do
        # force loading of winrm-transport to get the version constant
        require "winrm/transport/version"
      end

      it "logs a message to debug that code will be loaded" do
        transport.stubs(:require)
        transport

        logged_output.string.must_match debug_line_with(
          "Winrm Transport requested, loading WinRM::Transport gem")
      end

      it "logs a message to debug when library is initially loaded" do
        transport = Kitchen::Transport::Winrm.new(config)
        transport.stubs(:require)
        transport.stubs(:execute_block).returns(true)

        transport.finalize_config!(instance)

        logged_output.string.must_match(
          /WinRM::Transport library loaded/
        )
      end

      it "logs a message to debug when library is previously loaded" do
        transport = Kitchen::Transport::Winrm.new(config)
        transport.stubs(:require)
        transport.stubs(:execute_block).returns(false)

        transport.finalize_config!(instance)

        logged_output.string.must_match(
          /WinRM::Transport previously loaded/
        )
      end

      it "logs a message to fatal when libraries cannot be loaded" do
        transport = Kitchen::Transport::Winrm.new(config)
        transport.stubs(:require)
        transport.stubs(:execute_block).raises(LoadError, "uh oh")
        begin
          transport.finalize_config!(instance)
        rescue # rubocop:disable Lint/HandleExceptions
          # we are interested in the log output, not this exception
        end

        logged_output.string.must_match fatal_line_with(
          "The `winrm-transport` gem is missing and must be installed")
      end

      it "raises a UserError when libraries cannot be loaded" do
        transport = Kitchen::Transport::Winrm.new(config)
        transport.stubs(:require)
        transport.stubs(:execute_block).raises(LoadError, "uh oh")

        err = proc {
          transport.finalize_config!(instance)
        }.must_raise Kitchen::UserError
        err.message.must_match(/^Could not load or activate winrm-transport\. /)
      end
    end

    describe "winrm-s" do
      before do
        RbConfig::CONFIG.stubs(:[]).with("host_os").returns("mingw32")
      end

      it "logs a message to debug that code will be loaded" do
        transport = Kitchen::Transport::Winrm.new(config)
        transport.stubs(:load_winrm_transport!)
        transport.stubs(:require)
        transport.finalize_config!(instance)

        logged_output.string.must_match debug_line_with(
          "The winrm-s gem is being loaded")
      end

      it "logs a message to debug when library is initially loaded" do
        transport = Kitchen::Transport::Winrm.new(config)
        transport.stubs(:load_winrm_transport!)
        transport.stubs(:execute_block).returns(true)

        transport.finalize_config!(instance)

        logged_output.string.must_match(
          /winrm-s is loaded/
        )
      end

      it "logs a message to debug when library is previously loaded" do
        transport = Kitchen::Transport::Winrm.new(config)
        transport.stubs(:load_winrm_transport!)
        transport.stubs(:execute_block).returns(false)

        transport.finalize_config!(instance)

        logged_output.string.must_match(
          /winrm-s was already loaded/
        )
      end

      it "logs a message to fatal when libraries cannot be loaded" do
        transport = Kitchen::Transport::Winrm.new(config)
        transport.stubs(:load_winrm_transport!)
        transport.stubs(:execute_block).raises(LoadError, "uh oh")
        begin
          transport.finalize_config!(instance)
        rescue # rubocop:disable Lint/HandleExceptions
          # we are interested in the log output, not this exception
        end

        logged_output.string.must_match fatal_line_with(
          "The `winrm-s` gem is missing and must be installed")
      end

      it "raises a UserError when libraries cannot be loaded" do
        transport = Kitchen::Transport::Winrm.new(config)
        transport.stubs(:load_winrm_transport!)
        transport.stubs(:execute_block).raises(LoadError, "uh oh")

        err = proc {
          transport.finalize_config!(instance)
        }.must_raise Kitchen::UserError
        err.message.must_match(/^Could not load or activate winrm-s\. /)
      end
    end
  end

  def debug_line_with(msg)
    %r{^D, .* : #{Regexp.escape(msg)}}
  end

  def fatal_line_with(msg)
    %r{^F, .* : #{Regexp.escape(msg)}}
  end
end

describe Kitchen::Transport::Winrm::Connection do

  let(:logged_output)   { StringIO.new }
  let(:logger)          { Logger.new(logged_output) }

  let(:options) do
    { :logger => logger, :user => "me", :pass => "haha",
      :endpoint => "http://foo:5985/wsman", :winrm_transport => :plaintext,
      :kitchen_root => "/i/am/root", :instance_name => "coolbeans",
      :rdp_port => "rdpyeah" }
  end

  let(:info) do
    copts = { :user => "me", :pass => "haha" }
    "plaintext::http://foo:5985/wsman<#{copts}>"
  end

  let(:winrm_session) do
    s = mock("winrm_session")
    s.responds_like_instance_of(::WinRM::WinRMWebService)
    s
  end

  let(:executor) do
    s = mock("command_executor")
    s.responds_like_instance_of(WinRM::Transport::CommandExecutor)
    s
  end

  let(:connection) do
    Kitchen::Transport::Winrm::Connection.new(options)
  end

  before do
    logger.level = Logger::DEBUG
  end

  describe "#close" do

    let(:response) do
      o = WinRM::Output.new
      o[:exitcode] = 0
      o[:data].concat([{ :stdout => "ok\r\n" }])
      o
    end

    before do
      WinRM::Transport::CommandExecutor.stubs(:new).returns(executor)
      # disable finalizer as service is a fake anyway
      ObjectSpace.stubs(:define_finalizer).
        with { |obj, _| obj.class == Kitchen::Transport::Winrm::Connection }
      executor.stubs(:open).returns("shell-123")
      executor.stubs(:shell).returns("shell-123")
      executor.stubs(:close)
      executor.stubs(:run_powershell_script).
        with("doit").yields("ok\n", nil).returns(response)
    end

    it "logger displays closing connection on debug" do
      connection.execute("doit")
      connection.close

      logged_output.string.must_match debug_line(
        "[WinRM] closing remote shell shell-123 on #{info}"
      )
      logged_output.string.must_match debug_line(
        "[WinRM] remote shell shell-123 closed"
      )
    end

    it "only closes the shell once for multiple calls" do
      executor.expects(:close).once

      connection.execute("doit")
      connection.close
      connection.close
      connection.close
    end
  end

  describe "#execute" do

    before do
      WinRM::Transport::CommandExecutor.stubs(:new).returns(executor)
      # disable finalizer as service is a fake anyway
      ObjectSpace.stubs(:define_finalizer).
        with { |obj, _| obj.class == Kitchen::Transport::Winrm::Connection }
    end

    describe "for a successful command" do

      let(:response) do
        o = WinRM::Output.new
        o[:exitcode] = 0
        o[:data].concat([
          { :stdout => "ok\r\n" },
          { :stderr => "congrats\r\n" }
        ])
        o
      end

      before do
        executor.expects(:open).returns("shell-123")
        executor.expects(:run_powershell_script).
          with("doit").yields("ok\n", nil).returns(response)
      end

      it "logger displays command on debug" do
        connection.execute("doit")

        logged_output.string.must_match debug_line(
          "[WinRM] #{info} (doit)")
      end

      it "logger displays establishing connection on debug" do
        connection.execute("doit")

        logged_output.string.must_match debug_line(
          "[WinRM] opening remote shell on #{info}"
        )
        logged_output.string.must_match debug_line(
          "[WinRM] remote shell shell-123 is open on #{info}"
        )
      end

      it "logger captures stdout" do
        connection.execute("doit")

        logged_output.string.must_match(/^ok$/)
      end

      it "logger captures stderr on warn if logger is at debug level" do
        logger.level = Logger::DEBUG
        connection.execute("doit")

        logged_output.string.must_match warn_line("congrats")
      end

      it "logger does not log stderr on warn if logger is below debug level" do
        logger.level = Logger::INFO
        connection.execute("doit")

        logged_output.string.wont_match warn_line("congrats")
      end
    end

    describe "long command" do
      let(:command) { %{Write-Host "#{"a" * 4000}"} }

      let(:connection) do
        Kitchen::Transport::WinRMConnectionDummy.new(options)
      end

      let(:response) do
        o = WinRM::Output.new
        o[:exitcode] = 0
        o[:data].concat([
          { :stdout => "ok\r\n" },
          { :stderr => "congrats\r\n" }
        ])
        o
      end

      before do
        executor.expects(:open).returns("shell-123")
        executor.expects(:run_powershell_script).
          with(%{& "$env:TEMP/kitchen/coolbeans-long_script.ps1"}).
          yields("ok\n", nil).returns(response)
      end

      it "uploads the long command" do
        with_fake_fs do
          connection.execute(command)

          connection.saved_command.must_equal command
        end
      end
    end

    describe "for a failed command" do

      let(:response) do
        o = WinRM::Output.new
        o[:exitcode] = 1
        o[:data].concat([
          { :stderr => "#< CLIXML\r\n" },
          { :stderr => "<Objs Version=\"1.1.0.1\" xmlns=\"http://schemas." },
          { :stderr => "microsoft.com/powershell/2004/04\"><S S=\"Error\">" },
          { :stderr => "doit : The term 'doit' is not recognized as the " },
          { :stderr => "name of a cmdlet, function, _x000D__x000A_</S>" },
          { :stderr => "<S S=\"Error\">script file, or operable program. " },
          { :stderr => "Check the spelling of" },
          { :stderr => "the name, or if a path _x000D__x000A_</S><S S=\"E" },
          { :stderr => "rror\">was included, verify that the path is corr" },
          { :stderr => "ect and try again._x000D__x000A_</S><S S=\"Error" },
          { :stderr => "\">At line:1 char:1_x000D__x000A_</S><S S=\"Error" },
          { :stderr => "\">+ doit_x000D__x000A_</S><S S=\"Error\">+ ~~~~_" },
          { :stderr => "x000D__x000A_</S><S S=\"Error\">    + CategoryInf" },
          { :stderr => "o          : ObjectNotFound: (doit:String) [], Co" },
          { :stderr => "mmandNotFoun _x000D__x000A_</S><S S=\"Error\">   " },
          { :stderr => "dException_x000D__x000A_</S><S S=\"Error\">    + " },
          { :stderr => "FullyQualifiedErrorId : CommandNotFoundException_" },
          { :stderr => "x000D__x000A_</S><S S=\"Error\"> _x000D__x000A_</" },
          { :stderr => "S></Objs>" }
        ])
        o
      end

      before do
        executor.expects(:open).returns("shell-123")
        executor.expects(:run_powershell_script).
          with("doit").yields("nope\n", nil).returns(response)
      end

      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      def self.common_failed_command_specs
        it "logger displays command on debug" do
          begin
            connection.execute("doit")
          rescue # rubocop:disable Lint/HandleExceptions
            # the raise is not what is being tested here, rather its side-effect
          end

          logged_output.string.must_match debug_line(
            "[WinRM] #{info} (doit)"
          )
        end

        it "logger displays establishing connection on debug" do
          begin
            connection.execute("doit")
          rescue # rubocop:disable Lint/HandleExceptions
            # the raise is not what is being tested here, rather its side-effect
          end

          logged_output.string.must_match debug_line(
            "[WinRM] opening remote shell on #{info}"
          )
          logged_output.string.must_match debug_line(
            "[WinRM] remote shell shell-123 is open on #{info}"
          )
        end

        it "logger captures stdout" do
          begin
            connection.execute("doit")
          rescue # rubocop:disable Lint/HandleExceptions
            # the raise is not what is being tested here, rather its side-effect
          end

          logged_output.string.must_match(/^nope$/)
        end

        it "stderr is printed on logger warn level" do
          begin
            connection.execute("doit")
          rescue # rubocop:disable Lint/HandleExceptions
            # the raise is not what is being tested here, rather its side-effect
          end

          message = <<'MSG'.chomp!
doit : The term 'doit' is not recognized as the name of a cmdlet, function,
script file, or operable program. Check the spelling ofthe name, or if a path
was included, verify that the path is correct and try again.
At line:1 char:1
+ doit
+ ~~~~
    + CategoryInfo          : ObjectNotFound: (doit:String) [], CommandNotFoun
   dException
    + FullyQualifiedErrorId : CommandNotFoundException
MSG

          message.lines.each do |line|
            logged_output.string.must_match warn_line(line.chomp)
          end
        end
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

      describe "when a non-zero exit code is returned" do

        common_failed_command_specs

        it "raises a WinrmFailed exception" do
          err = proc {
            connection.execute("doit")
          }.must_raise Kitchen::Transport::WinrmFailed
          err.message.must_equal "WinRM exited (1) for command: [doit]"
        end
      end
    end

    describe "for a nil command" do

      it "does not log on debug" do
        executor.expects(:open).never
        connection.execute(nil)

        logged_output.string.must_equal ""
      end
    end

    [
      Errno::EACCES, Errno::EADDRINUSE, Errno::ECONNREFUSED,
      Errno::ECONNRESET, Errno::ENETUNREACH, Errno::EHOSTUNREACH,
      ::WinRM::WinRMHTTPTransportError, ::WinRM::WinRMAuthorizationError,
      HTTPClient::KeepAliveDisconnected, HTTPClient::ConnectTimeoutError
    ].each do |klass|
      describe "raising #{klass}" do

        before do
          k = if klass == ::WinRM::WinRMHTTPTransportError
            # this exception takes 2 args in its constructor, which is not stock
            klass.new("dang", 200)
          else
            klass
          end

          options[:connection_retries] = 3
          options[:connection_retry_sleep] = 7
          connection.stubs(:sleep)
          executor.stubs(:open).raises(k)
        end

        it "reraises the #{klass} exception" do
          proc { connection.execute("nope") }.must_raise klass
        end

        it "attempts to connect :connection_retries times" do
          begin
            connection.execute("nope")
          rescue # rubocop:disable Lint/HandleExceptions
            # the raise is not what is being tested here, rather its side-effect
          end

          logged_output.string.lines.count { |l|
            l =~ debug_line("[WinRM] opening remote shell on #{info}")
          }.must_equal 3
          logged_output.string.lines.count { |l|
            l =~ debug_line("[WinRM] remote shell shell-123 is open on #{info}")
          }.must_equal 0
        end

        it "sleeps for :connection_retry_sleep seconds between retries" do
          connection.unstub(:sleep)
          connection.expects(:sleep).with(7).twice

          begin
            connection.execute("nope")
          rescue # rubocop:disable Lint/HandleExceptions
            # the raise is not what is being tested here, rather its side-effect
          end
        end

        it "logs the first 2 retry failures on info" do
          begin
            connection.execute("nope")
          rescue # rubocop:disable Lint/HandleExceptions
            # the raise is not what is being tested here, rather its side-effect
          end

          logged_output.string.lines.count { |l|
            l =~ info_line_with(
              "[WinRM] connection failed, retrying in 7 seconds")
          }.must_equal 2
        end

        it "logs the last retry failures on warn" do
          begin
            connection.execute("nope")
          rescue # rubocop:disable Lint/HandleExceptions
            # the raise is not what is being tested here, rather its side-effect
          end

          logged_output.string.lines.count { |l|
            l =~ warn_line_with("[WinRM] connection failed, terminating ")
          }.must_equal 1
        end
      end
    end
  end

  describe "#login_command" do

    let(:login_command) { connection.login_command }
    let(:args)          { login_command.arguments.join(" ") }
    let(:exec_args)     { login_command.exec_args }

    let(:rdp_doc) do
      File.join(File.join(options[:kitchen_root], ".kitchen", "coolbeans.rdp"))
    end

    describe "for Mac-based workstations" do

      before do
        RbConfig::CONFIG.stubs(:[]).with("host_os").returns("darwin14")
      end

      it "returns a LoginCommand" do
        with_fake_fs do
          FileUtils.mkdir_p(File.dirname(rdp_doc))
          login_command.must_be_instance_of Kitchen::LoginCommand
        end
      end

      it "creates an rdp document" do
        actual = nil
        with_fake_fs do
          FileUtils.mkdir_p(File.dirname(rdp_doc))
          login_command
          actual = IO.read(rdp_doc)
        end

        actual.must_equal Kitchen::Util.outdent!(<<-RDP)
          drivestoredirect:s:*
          full address:s:foo:rdpyeah
          prompt for credentials:i:1
          username:s:me
        RDP
      end

      it "prints the rdp document on debug" do
        with_fake_fs do
          FileUtils.mkdir_p(File.dirname(rdp_doc))
          login_command
        end

        expected = Kitchen::Util.outdent!(<<-OUTPUT)
          Creating RDP document for coolbeans (/i/am/root/.kitchen/coolbeans.rdp)
          ------------
          drivestoredirect:s:*
          full address:s:foo:rdpyeah
          prompt for credentials:i:1
          username:s:me
          ------------
        OUTPUT
        debug_output(logged_output.string).must_match expected
      end

      it "returns a LoginCommand which calls open on the rdp document" do
        actual = nil
        with_fake_fs do
          FileUtils.mkdir_p(File.dirname(rdp_doc))
          actual = login_command
        end

        actual.exec_args.must_equal ["open", rdp_doc, {}]
      end
    end

    describe "for Windows-based workstations" do

      before do
        RbConfig::CONFIG.stubs(:[]).with("host_os").returns("mingw32")
      end

      it "returns a LoginCommand" do
        with_fake_fs do
          FileUtils.mkdir_p(File.dirname(rdp_doc))
          login_command.must_be_instance_of Kitchen::LoginCommand
        end
      end

      it "creates an rdp document" do
        actual = nil
        with_fake_fs do
          FileUtils.mkdir_p(File.dirname(rdp_doc))
          login_command
          actual = IO.read(rdp_doc)
        end

        actual.must_equal Kitchen::Util.outdent!(<<-RDP)
          full address:s:foo:rdpyeah
          prompt for credentials:i:1
          username:s:me
        RDP
      end

      it "prints the rdp document on debug" do
        with_fake_fs do
          FileUtils.mkdir_p(File.dirname(rdp_doc))
          login_command
        end

        expected = Kitchen::Util.outdent!(<<-OUTPUT)
          Creating RDP document for coolbeans (/i/am/root/.kitchen/coolbeans.rdp)
          ------------
          full address:s:foo:rdpyeah
          prompt for credentials:i:1
          username:s:me
          ------------
        OUTPUT
        debug_output(logged_output.string).must_match expected
      end

      it "returns a LoginCommand which calls mstsc on the rdp document" do
        actual = nil
        with_fake_fs do
          FileUtils.mkdir_p(File.dirname(rdp_doc))
          actual = login_command
        end

        actual.exec_args.must_equal ["mstsc", rdp_doc, {}]
      end
    end

    describe "for Linux-based workstations" do

      before do
        RbConfig::CONFIG.stubs(:[]).with("host_os").returns("linux-gnu")
      end

      it "returns a LoginCommand" do
        login_command.must_be_instance_of Kitchen::LoginCommand
      end

      it "is an rdesktop command" do
        login_command.command.must_equal "rdesktop"
        args.must_match %r{ foo:rdpyeah$}
      end

      it "sets the user" do
        args.must_match regexify("-u me ")
      end

      it "sets the pass if given" do
        args.must_match regexify(" -p haha ")
      end

      it "won't set the pass if not given" do
        options.delete(:pass)

        args.wont_match regexify(" -p haha ")
      end
    end

    describe "for unknown workstation platforms" do

      before do
        RbConfig::CONFIG.stubs(:[]).with("host_os").returns("cray")
      end

      it "raises an ActionFailed error" do
        err = proc { login_command }.must_raise Kitchen::ActionFailed
        err.message.must_equal "Remote login not supported in " \
          "Kitchen::Transport::Winrm::Connection from host OS 'cray'."
      end
    end
  end

  describe "#upload" do

    let(:transporter) do
      t = mock("file_transporter")
      t.responds_like_instance_of(WinRM::Transport::FileTransporter)
      t
    end

    before do
      # disable finalizer as service is a fake anyway
      ObjectSpace.stubs(:define_finalizer).
        with { |obj, _| obj.class == Kitchen::Transport::Winrm::Connection }

      WinRM::Transport::CommandExecutor.stubs(:new).returns(executor)
      executor.stubs(:open)

      WinRM::Transport::FileTransporter.stubs(:new).
        with(executor, logger).returns(transporter)
      transporter.stubs(:upload)
    end

    def self.common_specs_for_upload
      it "builds a Winrm::FileTransporter" do
        WinRM::Transport::FileTransporter.unstub(:new)

        WinRM::Transport::FileTransporter.expects(:new).
          with(executor, logger).returns(transporter)

        upload
      end

      it "reuses the Winrm::FileTransporter" do
        WinRM::Transport::FileTransporter.unstub(:new)

        WinRM::Transport::FileTransporter.expects(:new).
          with(executor, logger).returns(transporter).once

        upload
        upload
        upload
      end
    end

    describe "for a file" do

      def upload # execute every time, not lazily once
        connection.upload("/tmp/file.txt", "C:\\dest")
      end

      common_specs_for_upload
    end

    describe "for a collection of files" do

      def upload # execute every time, not lazily once
        connection.upload(%W[/tmp/file1.txt /tmp/file2.txt], "C:\\dest")
      end

      common_specs_for_upload
    end
  end

  describe "#wait_until_ready" do

    before do
      WinRM::Transport::CommandExecutor.stubs(:new).returns(executor)
      # disable finalizer as service is a fake anyway
      ObjectSpace.stubs(:define_finalizer).
        with { |obj, _| obj.class == Kitchen::Transport::Winrm::Connection }
      options[:max_wait_until_ready] = 300
      connection.stubs(:sleep)
    end

    describe "when failing to connect" do

      before do
        executor.stubs(:open).raises(Errno::ECONNREFUSED)
      end

      it "attempts to connect :max_wait_until_ready / 3 times if failing" do
        begin
          connection.wait_until_ready
        rescue # rubocop:disable Lint/HandleExceptions
          # the raise is not what is being tested here, rather its side-effect
        end

        logged_output.string.lines.count { |l|
          l =~ info_line_with(
            "Waiting for WinRM service on http://foo:5985/wsman, retrying in 3 seconds")
        }.must_equal((300 / 3) - 1)
        logged_output.string.lines.count { |l|
          l =~ debug_line_with("[WinRM] connection failed ")
        }.must_equal((300 / 3) - 1)
        logged_output.string.lines.count { |l|
          l =~ warn_line_with("[WinRM] connection failed, terminating ")
        }.must_equal 1
      end

      it "sleeps for 3 seconds between retries" do
        connection.unstub(:sleep)
        connection.expects(:sleep).with(3).times((300 / 3) - 1)

        begin
          connection.wait_until_ready
        rescue # rubocop:disable Lint/HandleExceptions
          # the raise is not what is being tested here, rather its side-effect
        end
      end
    end

    describe "when connection is successful" do

      let(:response) do
        o = WinRM::Output.new
        o[:exitcode] = 0
        o[:data].concat([{ :stdout => "[WinRM] Established\r\n" }])
        o
      end

      before do
        executor.stubs(:open).returns("shell-123")
        executor.expects(:run_powershell_script).
          with("Write-Host '[WinRM] Established\n'").returns(response)
      end

      it "executes an empty command string to ensure working" do
        connection.wait_until_ready
      end
    end

    describe "when connection suceeds but command fails, sad panda" do

      let(:response) do
        o = WinRM::Output.new
        o[:exitcode] = 42
        o[:data].concat([{ :stderr => "Ah crap.\r\n" }])
        o
      end

      before do
        executor.stubs(:open).returns("shell-123")
        executor.expects(:run_powershell_script).
          with("Write-Host '[WinRM] Established\n'").returns(response)
      end

      it "executes an empty command string to ensure working" do
        err = proc {
          connection.wait_until_ready
        }.must_raise Kitchen::Transport::WinrmFailed
        err.message.must_equal "WinRM exited (42) for command: " \
          "[Write-Host '[WinRM] Established\n']"
      end

      it "stderr is printed on logger warn level" do
        begin
          connection.wait_until_ready
        rescue # rubocop:disable Lint/HandleExceptions
          # the raise is not what is being tested here, rather its side-effect
        end

        logged_output.string.must_match warn_line("Ah crap.\n")
      end
    end
  end

  def debug_output(output)
    regexp = %r{^D, .* DEBUG -- : }
    output.lines.grep(%r{^D, .* DEBUG -- : }).map { |l| l.sub(regexp, "") }.join
  end

  def debug_line(msg)
    %r{^D, .* : #{Regexp.escape(msg)}$}
  end

  def debug_line_with(msg)
    %r{^D, .* : #{Regexp.escape(msg)}}
  end

  def info_line(msg)
    %r{^I, .* : #{Regexp.escape(msg)}$}
  end

  def info_line_with(msg)
    %r{^I, .* : #{Regexp.escape(msg)}}
  end

  def regexify(string)
    Regexp.new(Regexp.escape(string))
  end

  def warn_line(msg)
    %r{^W, .* : #{Regexp.escape(msg)}$}
  end

  def warn_line_with(msg)
    %r{^W, .* : #{Regexp.escape(msg)}}
  end
end
