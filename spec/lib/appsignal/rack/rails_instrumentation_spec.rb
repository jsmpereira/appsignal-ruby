if DependencyHelper.rails_present?
  class MockController
  end

  describe Appsignal::Rack::RailsInstrumentation do
    before :all do
      start_agent
    end

    let(:app) { double(:call => true) }
    let(:env) do
      http_request_env_with_data("action_dispatch.request_id" => "1").tap do |request|
        request["action_controller.instance"] = double(
          :class => MockController,
          :action_name => "index"
        )
      end
    end
    let(:middleware) { Appsignal::Rack::RailsInstrumentation.new(app, {}) }

    describe "#call" do
      before do
        allow(middleware).to receive(:raw_payload).and_return({})
      end

      context "when appsignal is active" do
        before { allow(Appsignal).to receive(:active?).and_return(true) }

        it "should call with monitoring" do
          expect(middleware).to receive(:call_with_appsignal_monitoring).with(env)
        end
      end

      context "when appsignal is not active" do
        before { allow(Appsignal).to receive(:active?).and_return(false) }

        it "should not call with monitoring" do
          expect(middleware).to_not receive(:call_with_appsignal_monitoring)
        end

        it "should call the app" do
          expect(app).to receive(:call).with(env)
        end
      end

      after { middleware.call(env) }
    end

    describe "#call_with_appsignal_monitoring" do
      it "should create a transaction" do
        expect(Appsignal::Transaction).to receive(:create).with(
          "1",
          Appsignal::Transaction::HTTP_REQUEST,
          kind_of(ActionDispatch::Request),
          :params_method => :filtered_parameters
        ).and_return(
          double(
            :set_action => nil,
            :set_http_or_background_queue_start => nil,
            :set_metadata => nil
          )
        )
      end

      it "should call the app" do
        expect(app).to receive(:call).with(env)
      end

      context "with an error" do
        let(:error) { VerySpecificError.new }
        let(:app) do
          double.tap do |d|
            allow(d).to receive(:call).and_raise(error)
          end
        end

        it "should set the error" do
          expect_any_instance_of(Appsignal::Transaction).to receive(:set_error).with(error)
        end
      end

      it "should set metadata" do
        expect_any_instance_of(Appsignal::Transaction).to receive(:set_metadata).twice
      end

      it "should set the action and queue start" do
        expect_any_instance_of(Appsignal::Transaction).to receive(:set_action).with("MockController#index")
        expect_any_instance_of(Appsignal::Transaction).to receive(:set_http_or_background_queue_start)
      end

      after { middleware.call(env) rescue VerySpecificError }
    end

    describe "#request_id" do
      subject { middleware.request_id(env) }

      context "with request id present" do
        let(:env) { { "action_dispatch.request_id" => "id" } }

        it "returns the present id" do
          is_expected.to eq "id"
        end
      end

      context "with request id not present" do
        let(:env) { {} }

        it "sets a new id" do
          expect(subject.length).to eq 36
        end
      end
    end
  end
end
