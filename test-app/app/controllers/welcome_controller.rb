class WelcomeController < ApplicationController

  def index
    sleep(rand())
    response_cache() do
      render text: File.read(File.join(Rails.root, "public", "thechivery.html"))
    end
  end

   def cache_age_tolerance_in_seconds
      1800
    end

end
