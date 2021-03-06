require "spec_helper"
require "net/http"
require "securerandom"
require "timeout"

describe "App CRUD" do
  CHECK_DELAY = 0.5.freeze
  ROUTING_TIMEOUT = 60

  with_user_with_org
  with_new_space
  with_time_limit

  it "creates/updates/deletes an app" do
    begin
      monitoring.record_action(:full_run) do
        monitoring.record_action(:create) do
          app_name = "crud"

          regular_user.clean_up_app_from_previous_run(app_name)
          @app = regular_user.create_app(@space, app_name)

          regular_user.clean_up_route_from_previous_run(app_name)
          @route = regular_user.create_route(@app, "#{app_name}-#{SecureRandom.uuid}")
        end

        monitoring.record_action(:read) do
          deploy_app(@app)
        end

        monitoring.record_action(:start) do
          start_app(@app)
        end

        monitoring.record_action(:app_routable) do
          check_app_routable(@route)
        end

        monitoring.record_action(:update) do
          scale_app(@app)
        end

        monitoring.record_action(:delete) do
          @route.delete!
          @app.delete!
          check_app_not_running(@route)
        end
      end

      monitoring.record_metric("crud_app.health", 1)
    rescue => e
      monitoring.record_metric("crud_app.health", 0)
      raise e
    end
  end

  def deploy_app(app)
    puts "starting #{__method__} (#{Time.now})"
    app.upload(File.expand_path("../../apps/java/JavaTinyApp-1.0.war", __FILE__))
  end

  def start_app(app)
    puts "starting #{__method__} (#{Time.now})"
    staging_log = ""
    app.start!(true) do |url|
      app.stream_update_log(url) do |chunk|
        staging_log << chunk
      end if url
    end

    check_app_started(app)
  rescue
    puts "Staging app log:\n#{staging_log}"
    raise
  end

  def check_app_started(app)
    puts "starting #{__method__} (#{Time.now})"
    sleep(CHECK_DELAY) until app.running?
  rescue CFoundry::NotStaged
    sleep(CHECK_DELAY)
    retry
  end

  def check_app_routable(route)
    puts "starting #{__method__} (#{Time.now})"
    app_uri = URI("http://#{route.host}.#{route.domain.name}")
    count = 0

    Timeout::timeout(ROUTING_TIMEOUT) do
      content = nil
      while content !~ /^It just needed to be restarted!/
        count += 1
        puts "checking that http://#{route.host}.#{route.domain.name} is routable attempt: #{count}."
        content = Net::HTTP.get(app_uri) rescue nil
        sleep 0.2
      end
    end
  end

  def scale_app(app)
    puts "starting #{__method__} (#{Time.now})"
    app.total_instances = 2
    app.update!

    sleep(CHECK_DELAY) until app.running?
  end

  def check_app_not_running(route)
    puts "starting #{__method__} (#{Time.now})"
    app_uri = URI("http://#{route.name}")

    response = Net::HTTP.get_response(app_uri)
    puts "--- GET #{app_uri}: #{response.class}"

    while response.is_a?(Net::HTTPSuccess)
      puts "--- GET #{app_uri}: #{response.class}"
      sleep(CHECK_DELAY)
      response = Net::HTTP.get_response(app_uri)
    end
  end
end
