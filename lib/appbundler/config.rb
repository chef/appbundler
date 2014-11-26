module Appbundler
  class Config

    # A list of files to exclude
    def self.exclusions
      @exclusions ||= []
    end
  end
end
