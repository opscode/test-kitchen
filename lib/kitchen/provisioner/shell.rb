# -*- encoding: utf-8 -*-
#
# Author:: Chris Lundquist (<chris.lundquist@github.com>)
#
# Copyright (C) 2013, Chris Lundquist
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

require "kitchen/provisioner/base"

module Kitchen

  module Provisioner

    # Basic shell provisioner.
    #
    # @author Chris Lundquist (<chris.ludnquist@github.com>)
    class Shell < Base

      default_config :script do |provisioner|
        provisioner.calculate_path("bootstrap.sh", :type => :file)
      end
      expand_path_for :script

      default_config :data_path do |provisioner|
        provisioner.calculate_path("data")
      end
      expand_path_for :data_path

      # (see Base#create_sandbox)
      def create_sandbox
        super
        prepare_data
        prepare_script
      end

      # (see Base#init_command)
      def init_command
        cmd = "#{sudo("rm -rf #{root_data_path}")} ; mkdir -p #{root_path}"

        Util.wrap_command(cmd)
      end

      # (see Base#run_command)
      def run_command
        cmd = sudo(root_script_path)

        Util.wrap_command(cmd)
      end

      private

      # Creates a data directory in the sandbox directory, if a data directory
      # can be found and copies in the tree.
      #
      # @api private
      def prepare_data
        return unless config[:data_path]

        info("Preparing data")
        debug("Using data from #{config[:data_path]}")

        tmpdata_dir = File.join(sandbox_path, "data")
        FileUtils.mkdir_p(tmpdata_dir)
        FileUtils.cp_r(Dir.glob("#{config[:data_path]}/*"), tmpdata_dir)
      end

      # Copies the executable script to the sandbox directory or creates a
      # stub script if one cannot be found.
      #
      # @api private
      def prepare_script
        info("Preparing script")

        if script
          debug("Using script from #{script}")
          FileUtils.cp_r(script, sandbox_path)
        else
          config[:script] = File.join(sandbox_path, "bootstrap.sh")
          info("#{File.basename(script)} not found " \
            "so Kitchen will run a stubbed script. Is this intended?")
          File.open(script, "wb") do |file|
            file.write(%{#!/bin/sh\necho "NO BOOTSTRAP SCRIPT PRESENT"\n})
          end
        end

        FileUtils.chmod(0755, File.join(sandbox_path, File.basename(script)))
      end

      # Returns a path string to the root directory.
      #
      # @return [String] path string
      # @api private
      def root_path
        config[:root_path]
      end

      # Returns a path string to the root data directory.
      #
      # @return [String] path string
      # @api private
      def root_data_path
        File.join(root_path, "data")
      end

      # Returns a path string to the root script.
      #
      # @return [String] path string
      # @api private
      def root_script_path
        script_name = File.basename(script)

        File.join(root_path, script_name)
      end

      # Returns a path string to the bootstrap script.
      #
      # @return [String] path string
      # @api private
      def script
        config[:script]
      end
    end
  end
end
