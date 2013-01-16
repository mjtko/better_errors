require "json"
require "ipaddr"

module BetterErrors
  # Better Errors' error handling middleware. Including this in your middleware
  # stack will show a Better Errors error page for exceptions raised below this
  # middleware.
  # 
  # If you are using Ruby on Rails, you do not need to manually insert this 
  # middleware into your middleware stack to use it with its default options.
  # If you wish to configure the middleware, an initializer in
  # application.rb to set middleware options is required:
  #
  # @example Rails
  #    config.before_initialize do
  #      unless Rails.env.production?
  #        BetterErrors.middleware_opts = {:handler => MyErrorPage}
  #      end
  #    end
  #
  # @example Sinatra
  #   require "better_errors"
  # 
  #   if development?
  #     use BetterErrors::Middleware
  #   end
  #
  # @example Rack
  #   require "better_errors"
  #   if ENV["RACK_ENV"] == "development"
  #     use BetterErrors::Middleware
  #   end
  # 
  class Middleware
    # A new instance of BetterErrors::Middleware
    # 
    # @param app      The Rack app/middleware to wrap with Better Errors
    # @param opts     [Hash] containing options for configuration of the middleware
    def initialize(app, opts = BetterErrors.middleware_opts)
      opts ||= {}
      @app = app
      if opts.is_a?(Class)
        warn "[DEPRECATION] Passing a Class for an error page handler is deprecated.  Please use the `:handler` key in an options Hash instead. (called from: #{Kernel.caller.first})"
        @handler = opts
        opts = {}
      else
        @handler = opts[:handler] || ErrorPage
      end
      @except = *(opts[:except])
      @except << EXCEPT_XHR if opts[:skip_xhr]
    end
    
    # Calls the Better Errors middleware
    # 
    # @param [Hash] env
    # @return [Array]
    def call(env)
      if local_request? env
        better_errors_call env
      else
        @app.call env
      end
    end
    
  private
    IPV4_LOCAL = IPAddr.new("127.0.0.0/8")
    IPV6_LOCAL = IPAddr.new("::1/128")
    EXCEPT_XHR = proc { |env| env['HTTP_X_REQUESTED_WITH'] == 'XMLHttpRequest' }

    def local_request?(env)
      # REMOTE_ADDR is not in the rack spec, so some application servers do
      # not provide it.
      return true unless env["REMOTE_ADDR"]
      ip = IPAddr.new env["REMOTE_ADDR"]
      IPV4_LOCAL.include? ip or IPV6_LOCAL.include? ip
    end

    def better_errors_call(env)
      case env["PATH_INFO"]
      when %r{\A/__better_errors/(?<oid>-?\d+)/(?<method>\w+)\z}
        internal_call env, $~
      when %r{\A/__better_errors/?\z}
        show_error_page env
      else
        protected_app_call env
      end
    end

    def protected_app_call(env)
      @app.call env
    rescue Exception => ex
      raise if @except.any? { |c| c.call(env, ex) }
      @error_page = @handler.new ex, env
      log_exception
      show_error_page(env)
    end
    
    def show_error_page(env)
      content = if @error_page
        @error_page.render
      else
        "<h1>No errors</h1><p>No errors have been recorded yet.</p><hr>" +
        "<code>Better Errors v#{BetterErrors::VERSION}</code>"
      end

      [500, { "Content-Type" => "text/html; charset=utf-8" }, [content]]
    end

    
    def log_exception
      return unless BetterErrors.logger
      
      message = "\n#{@error_page.exception.class} - #{@error_page.exception.message}:\n"
      @error_page.backtrace_frames.each do |frame|
        message << "  #{frame}\n"
      end
      
      BetterErrors.logger.fatal message
    end
  
    def internal_call(env, opts)
      if opts[:oid].to_i != @error_page.object_id
        return [200, { "Content-Type" => "text/plain; charset=utf-8" }, [JSON.dump(error: "Session expired")]]
      end
      
      response = @error_page.send("do_#{opts[:method]}", JSON.parse(env["rack.input"].read))
      [200, { "Content-Type" => "text/plain; charset=utf-8" }, [JSON.dump(response)]]
    end
  end
end
