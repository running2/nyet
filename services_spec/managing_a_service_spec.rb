require "spec_helper"
require "fileutils"

describe "Managing a Service", :only_in_staging => true, :appdirect => true do
  let(:plan_name) { "small" }
  let(:service_name) { "dummy-dev" }
  let(:service_instance_name) { "service-management-tester" }
  let(:app_name) { "services-management-nyet-app" }

  let(:test_app_path) { File.expand_path("../apps/ruby/app_sinatra_service", File.dirname(__FILE__)) }
  let(:tmp_dir) { File.expand_path("../tmp", File.dirname(__FILE__)) }
  let(:fake_home) { File.join(tmp_dir, 'fake_home') }
  let(:cf_bin)  { File.join(bin_dir, 'cf') }
  let(:bin_dir) { File.join(tmp_dir, 'bin') }
  let(:gem_dir) { File.join(tmp_dir, 'gems') }


  with_user_with_org
  with_shared_space

  around do |example|
    original_env = ENV.to_hash
    Bundler.with_clean_env do
      example.call
    end
    ENV.replace(original_env)
  end

  before do
    FileUtils.rm_rf tmp_dir
    FileUtils.mkdir_p fake_home
    FileUtils.mkdir_p bin_dir
    FileUtils.mkdir_p gem_dir

    ENV['HOME'] = fake_home

    use_newest_cf
    login

    clean_up_service_instance(service_instance_name)
    regular_user.clean_up_route_from_previous_run(app_name)
    clean_up_app(app_name)
  end

  after do
    clean_up_service_instance(service_instance_name)
    regular_user.clean_up_route_from_previous_run(app_name)
    clean_up_app(app_name)
  end

  it "allows the user to push an app with a newly created service and bind it" do
    Dir.chdir(test_app_path) do
      BlueShell::Runner.run("#{cf_bin} push --no-manifest") do |runner|
        runner.should say "Name>"
        runner.send_keys app_name

        runner.should say "Instances>"
        runner.send_keys "1"

        runner.should say "Memory Limit>"
        runner.send_keys "128M"

        runner.should say "Subdomain> #{app_name}"
        runner.send_keys app_name

        runner.should say "Domain>"
        runner.send_return

        runner.should say "Create services for application?>"
        runner.send_keys "y"

        runner.should say "What kind?>"
        runner.send_keys "#{service_name} n/a"

        runner.should say "Name?>"
        runner.send_keys service_instance_name

        runner.should say "Which plan?>"
        runner.send_keys plan_name

        runner.should say /Creating service #{service_instance_name}.*OK/
        runner.should say /Binding .+ to .+ OK/

        runner.should say "Create another service?>"
        runner.send_keys "n"

        runner.should say "Bind other services to application?>"
        runner.send_keys "n"

        runner.should say "Uploading #{app_name}... OK", 180
        runner.should say "Preparing to start #{app_name}... OK", 180
        runner.should say "Checking status of app '#{app_name}'", 180
        runner.should say "1 of 1 instances running"
        runner.should say "Push successful!", 30
      end
    end
  end

  def use_newest_cf
    ENV['GEM_HOME'] = gem_dir
    ENV['GEM_PATH'] = gem_dir

    system("gem install --install-dir #{gem_dir} --bindir #{bin_dir} --no-ri --no-rdoc cf 2>&1 >/dev/null") or
      raise "Couldn't download latest cf"

    puts "Installed the newest version of cf gem: #{`#{cf_bin} --version`.chomp}"
  end

  def login
    set_target
    logout

    username = ENV['NYET_REGULAR_USERNAME']
    password = ENV['NYET_REGULAR_PASSWORD']

    cmd = "#{cf_bin} login #{username} --password #{password} -o #{org.name} -s #{space.name}"
    BlueShell::Runner.run(cmd) do |runner|
      runner.wait_for_exit 60
    end
  end

  def logout
    BlueShell::Runner.run("#{cf_bin} logout") do |runner|
      runner.wait_for_exit 60
    end
  end

  def set_target
    target = ENV['NYET_TARGET']
    BlueShell::Runner.run("#{cf_bin} target #{target}") do |runner|
      runner.wait_for_exit(20)
    end
  end

  def clean_up_service_instance(service_instance_name)
    if service_instance = space.service_instance_by_name(service_instance_name)
      service_instance.delete!(recursive: true)
    end
  end

  def clean_up_app(app_name)
    if app = space.app_by_name(app_name)
      app.delete!(recursive: true)
    end
  end

end
