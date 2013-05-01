class WelcomeController < ApplicationController

  def index
    sleep(rand())
    response_cache() do
      render text: ("Some text" * 2048)
    end
  end

   def cache_age_tolerance_in_seconds
      1800
    end

end
