# frozen_string_literal: true

require 'spec_helper'
require 'bolt/pal/yaml_plan/transpiler'
require 'bolt_spec/config'
require 'bolt_spec/integration'

describe "transpiling YAML plans" do
  include BoltSpec::Config
  include BoltSpec::Integration

  after(:each) { Puppet.settings.send(:clear_everything_for_tests) }
  let(:modulepath) { fixture_path('modules') }
  let(:yaml_path) { File.join(modulepath, 'yaml', 'plans') }
  let(:plan_path) { File.join(yaml_path, 'conversion.yaml') }
  let(:output_plan) { <<~PLAN }
  # A yaml plan for testing plan conversion
  # WARNING: This is an autogenerated plan. It may not behave as expected.
  # @param targets The targets to run the plan on
  # @param message A string to print
  plan yaml::conversion(
    TargetSpec $targets,
    String $message = 'hello world'
  ) {
    $sample = run_task('sample', $targets, {'message' => $message})
    apply_prep($targets)
    apply($targets) {
      package { 'nginx': }
      ->
      file { '/etc/nginx/html/index.html':
        content => "Hello world!",
      }
      ->
      service { 'nginx': }
    }
    $eval_output = with() || {
      # TODO: Can blocks handle comments?
      $list = $sample.targets.map |$t| {
        notice($t)
        $t
      }
      $list.map |$l| {$l.name}
    }

    return $eval_output
  }
  PLAN

  it 'transpiles a yaml plan' do
    expect {
      run_cli(['plan', 'convert', plan_path])
    }.to output(output_plan).to_stdout
  end

  it 'plan show output is the same for the original plan and converted plan', ssh: true do
    Dir.mktmpdir do |tmpdir|
      FileUtils.mkdir_p(File.join(tmpdir, 'plans'))
      File.write(File.join(tmpdir, 'plans', 'conversion.pp'), output_plan)
      File.write(File.join(tmpdir, 'bolt-project.yaml'), { 'name' => 'yaml' }.to_yaml)
      puppet_show = JSON.parse(run_cli(%W[plan show yaml::conversion --project #{tmpdir}]))
      yaml_show = JSON.parse(run_cli(%W[plan show yaml::conversion -m #{modulepath}]))

      # Don't compare moduledirs
      [puppet_show, yaml_show].each do |plan|
        plan.delete_if { |k, _v| k == 'module_dir' }
      end

      # Remove the conversion warning
      suffix = "\nWARNING: This is an autogenerated plan. It may not behave as expected."
      puppet_show['description'].delete_suffix!(suffix)

      # Account for string quoting
      yaml_show['parameters']['message']['default_value'] = "'#{yaml_show['parameters']['message']['default_value']}'"

      expect(puppet_show).to eq(yaml_show)
    end
  end
end
