require "spec_helper"

describe "Managing SendGrid", :service => true, :appdirect => true do
  let(:app_name) { "sendgrid" }
  let(:namespace) { "smtp" }
  let(:plan_name) { "free" }
  let(:service_name) { "sendgrid-dev" }

  it "allows users to create, bind, send emails, unbind, and delete the SendGrid service" do
    create_and_use_service do |client|
      client.send_email("john@example.com").should be_a Net::HTTPSuccess
    end
  end
end
