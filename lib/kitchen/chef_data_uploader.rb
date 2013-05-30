# -*- encoding: utf-8 -*-
#
# Author:: Fletcher Nichol (<fnichol@nichol.ca>)
#
# Copyright (C) 2012, Fletcher Nichol
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

require 'fileutils'
require 'json'
require 'net/scp'
require 'stringio'

module Kitchen

  # Uploads Chef asset files such as dna.json, data bags, and cookbooks to an
  # instance over SSH.
  #
  # @author Fletcher Nichol <fnichol@nichol.ca>
  class ChefDataUploader

    include ShellOut
    include Logging

    def initialize(instance, ssh_args, kitchen_root, chef_home)
      @instance = instance
      @ssh_args = ssh_args
      @kitchen_root = kitchen_root
      @chef_home = chef_home
    end

    def upload
      Net::SCP.start(*ssh_args) do |scp|
        upload_json       scp
        upload_solo_rb    scp
        upload_cookbooks  scp
        upload_data_bags  scp if instance.suite.data_bags_path
        upload_roles      scp if instance.suite.roles_path
        upload_secret scp if instance.suite.encrypted_data_bag_secret_key_path
      end
    end

    private

    attr_reader :instance, :ssh_args, :kitchen_root, :chef_home

    def logger
      instance.logger
    end

    def upload_json(scp)
      json_file = StringIO.new(instance.dna.to_json)
      scp.upload!(json_file, "#{chef_home}/dna.json")
    end

    def upload_solo_rb(scp)
      solo_rb_file = StringIO.new(solo_rb_contents)
      scp.upload!(solo_rb_file, "#{chef_home}/solo.rb")
    end

    def upload_cookbooks(scp)
      cookbooks_dir = local_cookbooks
      upload_path(scp, cookbooks_dir, "cookbooks")
    ensure
      FileUtils.rmtree(cookbooks_dir) unless cookbooks_dir.nil?
    end

    def upload_data_bags(scp)
      upload_path(scp, instance.suite.data_bags_path)
    end

    def upload_roles(scp)
      upload_path(scp, instance.suite.roles_path)
    end

    def upload_secret(scp)
      scp.upload!(instance.suite.encrypted_data_bag_secret_key_path,
        "#{chef_home}/encrypted_data_bag_secret")
    end

    def upload_path(scp, path, dir = File.basename(path))
      dest = "#{chef_home}/#{dir}"

      scp.upload!(path, dest, :recursive => true) do |ch, name, sent, total|
        if sent == total
          info("Uploaded #{name.sub(%r{^#{path}/}, '')} (#{total} bytes)")
        end
      end
    end

    def solo_rb_contents
      solo = []
      solo << %{node_name "#{instance.name}"}
      solo << %{file_cache_path "#{chef_home}/cache"}
      solo << %{cookbook_path "#{chef_home}/cookbooks"}
      solo << %{role_path "#{chef_home}/roles"}
      if instance.suite.data_bags_path
        solo << %{data_bag_path "#{chef_home}/data_bags"}
      end
      if instance.suite.encrypted_data_bag_secret_key_path
        secret = "#{chef_home}/encrypted_data_bag_secret"
        solo << %{encrypted_data_bag_secret "#{secret}"}
      end
      solo.join("\n")
    end

    def local_cookbooks
      tmpdir = Dir.mktmpdir("#{instance.name}-cookbooks")
      prepare_tmpdir(tmpdir)
      tmpdir
    end

    def prepare_tmpdir(tmpdir)
      if File.exists?(berksfile)
        resolve_with_berkshelf(tmpdir)
      elsif File.exists?(cheffile)
        resolve_with_librarian(tmpdir)
      elsif File.directory?(File.join(kitchen_root, "cookbooks"))
        cp_cookbooks(tmpdir)
      elsif File.exists?(File.join(kitchen_root, "metadata.rb"))
        cp_this_cookbook(tmpdir)
      else
        FileUtils.rmtree(tmpdir)
        fatal("Berksfile, Cheffile, cookbooks/, or metadata.rb" +
          " must exist in #{kitchen_root}")
        raise UserError, "Cookbooks could not be found"
      end

      filter_only_cookbook_files(tmpdir)
    end

    def filter_only_cookbook_files(tmpdir)
      all_files = Dir.glob(File.join(tmpdir, "**/*")).
        select { |fn| File.file?(fn) }
      cookbook_files = Dir.glob(File.join(tmpdir, cookbook_files_glob)).
        select { |fn| File.file?(fn) }

      FileUtils.rm(all_files - cookbook_files)
    end

    def cookbook_files_glob
      files = %w{README.* metadata.{json,rb}
        attributes/**/* definitions/**/* files/**/* libraries/**/*
        providers/**/* recipes/**/* resources/**/* templates/**/*}

      "*/{#{files.join(',')}}"
    end

    def berksfile
      File.join(kitchen_root, "Berksfile")
    end

    def cheffile
      File.join(kitchen_root, "Cheffile")
    end

    def cp_cookbooks(tmpdir)
      FileUtils.cp_r(File.join(kitchen_root, "cookbooks", "."), tmpdir)
      cp_this_cookbook(tmpdir) if File.exists?(File.expand_path('metadata.rb'))
    end

    def cp_this_cookbook(tmpdir)
      metadata_rb = File.join(kitchen_root, "metadata.rb")
      cb_name = MetadataChopper.extract(metadata_rb).first or raise(UserError,
        "The metadata.rb does not define the 'name' key." +
          " Please add: `name '<cookbook_name>'` to metadata.rb and try again")

      cb_path = File.join(tmpdir, cb_name)
      glob = Dir.glob("#{kitchen_root}/{metadata.rb,README.*," +
        "attributes,files,libraries,providers,recipes,resources,templates}")

      FileUtils.mkdir_p(cb_path)
      FileUtils.cp_r(glob, cb_path)
    end

    def resolve_with_berkshelf(tmpdir)
      info("Resolving cookbook dependencies with Berkshelf using #{berksfile}")

      begin
        require 'berkshelf'
      rescue LoadError
        fatal("The `berkself' gem is missing and must be installed." +
          " Run `gem install berkshelf` or add the following " +
          "to your Gemfile if you are using Bundler: `gem 'berkshelf'`.")
        raise UserError, "Could not load Berkshelf to resolve dependencies"
      end

      Kitchen.mutex.synchronize do
        Berkshelf::Berksfile.from_file(berksfile).install(:path => tmpdir)
      end
    end

    def resolve_with_librarian(tmpdir)
      info("Resolving cookbook dependencies with Librarian-Chef using #{cheffile}")

      begin
        require 'librarian/chef/environment'
        require 'librarian/action/resolve'
        require 'librarian/action/install'
      rescue LoadError
        fatal("The `librarian-chef' gem is missing and must be installed." +
          " Run `gem install librarian-chef` or add the following " +
          "to your Gemfile if you are using Bundler: `gem 'librarian-chef'`.")
        raise UserError, "Could not load Librarian-Chef to resolve dependencies"
      end

      Kitchen.mutex.synchronize do
        env = Librarian::Chef::Environment.new
        env.config_db.local["path"] = tmpdir
        Librarian::Action::Resolve.new(env).run
        Librarian::Action::Install.new(env).run
      end
    end
  end
end
