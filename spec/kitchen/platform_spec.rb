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

require_relative '../spec_helper'

require 'kitchen/errors'
require 'kitchen/platform'

describe Kitchen::Platform do

  let(:opts) do ; { :name => 'plata' } ; end
  let(:platform) { Kitchen::Platform.new(opts) }

  it "raises an ArgumentError if name is missing" do
    opts.delete(:name)
    proc { Kitchen::Platform.new(opts) }.must_raise Kitchen::ClientError
  end

  describe 'Cheflike' do

    let(:platform) do
      Kitchen::Platform.new(opts).extend(Kitchen::Platform::Cheflike)
    end

    it "returns an empty Array given no run_list" do
      platform.run_list.must_equal []
    end

    it "returns an empty Hash given no attributes" do
      platform.attributes.must_equal Hash.new
    end

    it "returns attributes from constructor" do
      opts.merge!({ :run_list => ['a', 'b'], :attributes => { :c => 'd' } })
      platform.name.must_equal 'plata'
      platform.run_list.must_equal ['a', 'b']
      platform.attributes.must_equal({ :c => 'd' })
    end
  end
end
