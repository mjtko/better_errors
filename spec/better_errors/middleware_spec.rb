require "spec_helper"

module BetterErrors
  describe Middleware do
    let(:app) { Middleware.new(->env { ":)" }) }

    it "should pass non-error responses through" do
      app.call({}).should == ":)"
    end

    it "should call the internal methods" do
      app.should_receive :internal_call
      app.call("PATH_INFO" => "/__better_errors/1/preform_awesomness")
    end

    it "should show the error page" do
      app.should_receive :show_error_page
      app.call("PATH_INFO" => "/__better_errors/")
    end

    it "should not show the error page to a non-local address" do
      app.should_not_receive :better_errors_call
      app.call("REMOTE_ADDR" => "1.2.3.4")
    end

    context "when requesting the /__better_errors manually" do
      let(:app) { Middleware.new(->env { ":)" }) }
      
      it "should show that no errors have been recorded" do
        status, headers, body = app.call("PATH_INFO" => "/__better_errors")
        body.join.should match /No errors have been recorded yet./
      end
    end
    
    context "when handling an error" do
      let(:app) { Middleware.new(->env { raise "oh no :(" }) }
    
      it "should return status 500" do
        status, headers, body = app.call({})
      
        status.should == 500
      end
    
      it "should return UTF-8 error pages" do
        status, headers, body = app.call({})
        
        headers["Content-Type"].should == "text/html; charset=utf-8"
      end
      
      it "should log the exception" do
        logger = Object.new
        logger.should_receive :fatal
        BetterErrors.stub!(:logger).and_return(logger)
        
        app.call({})
      end

      context "with handler supplied as Class" do
        let(:app) do
          Middleware.new(->env { raise "oh no :(" }, 
                         ErrorPage)
        end
        
        it "should return status 500" do
          status, headers, body = app.call({})
          status.should == 500
        end
      end

      context "with handler supplied as option" do
        let(:app) do
          Middleware.new(->env { raise "oh no :(" }, 
                         :handler => ErrorPage)
        end
        
        it "should return status 500" do
          status, headers, body = app.call({})
          status.should == 500
        end
      end

      context "with except condition supplied as option" do
        let(:app) do
          Middleware.new(->env { raise "oh no :(" },
                         :except => proc { |env| env['FAIL'] == true })
        end
        
        it "should raise the exception" do
          expect { app.call({'FAIL' => true}) }.to raise_error
        end

        it "should not raise the exception" do
          expect { app.call({}) }.to_not raise_error
        end
      end

      context "with multiple except conditions supplied as option" do
        let(:app) do
          Middleware.new(->env { raise env['MESSAGE'] }, 
                         :except => [proc { |env, ex| env['FAIL'] == true },
                                     proc { |env, ex| ex.message == 'reraise this' }] )
        end
        
        it "should raise the exception" do
          expect { app.call({'FAIL' => true}) }.to raise_error
          expect { app.call({'MESSAGE' => 'reraise this', 'FAIL' => false}) }.to raise_error
        end

        it "should not raise the exception" do
          expect { app.call({}) }.to_not raise_error
        end
      end

      context "with skip_xhr option supplied" do
        let(:app) do
          Middleware.new(->env { raise 'oh no :-(' }, 
                         :skip_xhr => true)
        end
        
        it "should raise the exception when X-Requested-With is set to 'XMLHttpRequest'" do
          expect { app.call({'HTTP_X_REQUESTED_WITH' => 'XMLHttpRequest'}) }.to raise_error
        end

        it "should not raise the exception for other requests" do
          expect { app.call({}) }.to_not raise_error
        end
      end
    end
  end
end
