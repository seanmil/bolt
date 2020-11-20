# frozen_string_literal: true

require 'pathname'
require 'spec_helper'
require 'bolt/project_manager'
require 'bolt/module_installer'
require 'bolt_spec/project'

describe Bolt::ProjectManager do
  include BoltSpec::Project

  let(:config)    { Bolt::Config.from_project(project) }
  let(:pal)       { double('pal', generate_types: nil) }

  let(:outputter) {
    double('outputter',
           print_message: nil,
           print_action_step: nil,
           print_prompt: nil,
           print_error: nil)
  }

  let(:manager)            { described_class.new(config, outputter, pal) }
  let(:config_migrator)    { double('config_migrator',    migrate: true) }
  let(:inventory_migrator) { double('inventory_migrator', migrate: true) }
  let(:module_migrator)    { double('module_migrator',    migrate: true) }

  around :each do |example|
    with_project do
      example.run
    end
  end

  context '#create' do
    before(:each) do
      delete_config
    end

    it 'creates a new project' do
      manager.create(project_path, nil, nil)
      expect(config_path.exist?).to be
      expect(YAML.load_file(config_path)).to include('name' => File.basename(project_path))
    end

    it 'creates a new project with the specified name' do
      manager.create(project_path, 'myproject', nil)
      expect(config_path.exist?).to be
      expect(YAML.load_file(config_path)).to include('name' => 'myproject')
    end

    it 'configures modules with an empty array' do
      manager.create(project_path, nil, nil)
      expect(YAML.load_file(config_path)).to include('modules' => [])
    end

    it 'errors if the directory name is invalid' do
      dir = tmpdir + 'MyProject'
      FileUtils.mkdir(dir)
      expect { manager.create(dir, nil, nil) }.to raise_error(
        Bolt::ValidationError,
        /The current directory name 'MyProject' is an invalid project name/
      )
    end

    it 'errors if the specified name is invalid' do
      expect { manager.create(project_path, 'MyProject', nil) }.to raise_error(
        Bolt::ValidationError,
        /The provided project name 'MyProject' is invalid/
      )
    end

    it 'errors if bolt-project.yaml already exists' do
      FileUtils.touch(config_path)
      expect { manager.create(project_path, nil, nil) }.to raise_error(
        Bolt::Error,
        /Found existing project directory with bolt-project.yaml/
      )
    end

    it 'errors if bolt.yaml already exists' do
      FileUtils.touch(project_path + 'bolt.yaml')
      expect { manager.create(project_path, nil, nil) }.to raise_error(
        Bolt::Error,
        /Found existing project directory with bolt.yaml/
      )
    end

    context 'with modules' do
      let(:modules)   { ['puppetlabs/yaml'] }
      let(:installer) { double('installer', install: true) }

      before(:each) do
        allow(Bolt::ModuleInstaller).to receive(:new).and_return(installer)
      end

      it 'creates a Puppetfile and installs modules' do
        expect(installer).to receive(:install).with(modules, project.puppetfile, project.managed_moduledir)
        manager.create(project_path, nil, modules)
      end

      it 'configures modules with the specified modules' do
        manager.create(project_path, nil, modules)
        expect(YAML.load_file(config_path)).to include('modules' => modules)
      end

      it 'errors if bolt-project.yaml already exists' do
        FileUtils.touch(config_path)
        expect { manager.create(project_path, nil, modules) }.to raise_error(
          Bolt::Error,
          /Found existing project directory with bolt-project.yaml.*with modules/
        )
      end

      it 'errors with an existing Puppetfile' do
        FileUtils.touch(project.puppetfile)
        expect { manager.create(project_path, nil, modules) }.to raise_error(
          Bolt::Error,
          /Found existing Puppetfile/
        )
      end
    end
  end

  context '#migrate' do
    before(:each) do
      allow($stdin).to receive(:tty?).and_return(true)
      allow(Bolt::Util).to receive(:prompt_yes_no).and_return(true)
      allow(Bolt::ProjectManager::ConfigMigrator).to receive(:new).and_return(config_migrator)
      allow(Bolt::ProjectManager::InventoryMigrator).to receive(:new).and_return(inventory_migrator)
      allow(Bolt::ProjectManager::ModuleMigrator).to receive(:new).and_return(module_migrator)
    end

    it 'errors if stdin is not a tty' do
      allow($stdin).to receive(:tty?).and_return(false)
      expect { manager.migrate }.to raise_error(
        Bolt::Error,
        /stdin is not a tty/
      )
    end

    it 'migrates config' do
      expect(config_migrator).to receive(:migrate)
      manager.migrate
    end

    it 'migrates inventory' do
      expect(inventory_migrator).to receive(:migrate)
      manager.migrate
    end

    it 'migrates modules' do
      expect(module_migrator).to receive(:migrate)
      manager.migrate
    end

    it 'returns 0 if all migrations succeeded' do
      expect(manager.migrate).to eq(0)
    end

    it 'returns 1 if any migrations failed' do
      allow(Bolt::ProjectManager::ConfigMigrator).to receive(:new).and_return(double('config_migrator', migrate: false))
      expect(manager.migrate).to eq(1)
    end
  end
end