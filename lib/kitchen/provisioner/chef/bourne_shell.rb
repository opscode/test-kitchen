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

module Kitchen

  module Provisioner

    module Chef

      # Provides commands for interacting with chef on a test instance
      #
      # @author Matt Wrock <matt@mattwrock.com>
      module BourneShell

        # The path to the root of a chef install
        #
        # @return [String] absolute path to chef root
        def chef_omnibus_root
          "/opt/chef"
        end

        # path to chef-solo relative to the chef_omnibus_root
        #
        # @return [String] path to chef solo
        def chef_solo_file
          "bin/chef-solo"
        end

        # path to chef-client relative to the chef_omnibus_root
        #
        # @return [String] path to chef client
        def chef_client_file
          "bin/chef-client"
        end

        # A command for initializing an instance for working with chef
        # the calling provisioner may have a omnibus root configured by
        # the user that is different from this module's chef_omnibus_root.
        #
        # @param root_path [String] root path to chef omnibus
        # @return [String] command to run on instance initializing
        # chef environment
        def init_command(root_path)
          dirs = %w[cookbooks data data_bags environments roles clients].
            map { |dir| File.join(root_path, dir) }.join(" ")
          lines = ["#{sudo("rm")} -rf #{dirs}", "mkdir -p #{root_path}"]

          wrap_command([dirs, lines].join("\n"))
        end

        # File name containing helper scripts for working with the chef
        # environment on the test instance.
        #
        # @return [String] helper file name
        def chef_helper_file
          "chef_helpers.sh"
        end

        # Install script for the chef client on the test instance.
        #
        # @param version [String] the chef version to install
        # @param config [Hash] the calling provisioner's config
        # @option opts [String] :chef_omnibus_install_options install
        # options to pass to installer
        # @option opts [String] :chef_omnibus_root path to the chef omnibus root
        # @option opts [String] :chef_omnibus_url URL to download the chef installer
        # @return [String] command to install chef
        def install_function(version, config)
          pretty_version = case version
                           when "true" then "install only if missing"
                           when "latest" then "always install latest version"
                           else version
                           end
          install_flags = %w[latest true].include?(version) ? "" : "-v #{version}"
          if config[:chef_omnibus_install_options]
            install_flags += config[:chef_omnibus_install_options]
          end

          <<-INSTALL.gsub(/^ {10}/, "")
            if should_update_chef "#{config[:chef_omnibus_root]}" "#{version}" ; then
              echo "-----> Installing Chef Omnibus (#{pretty_version})"
              do_download #{config[:chef_omnibus_url]} /tmp/install.sh
              #{sudo("sh")} /tmp/install.sh #{install_flags}
            else
              echo "-----> Chef Omnibus installation detected (#{pretty_version})"
            fi
          INSTALL
        end
      end
    end
  end
end