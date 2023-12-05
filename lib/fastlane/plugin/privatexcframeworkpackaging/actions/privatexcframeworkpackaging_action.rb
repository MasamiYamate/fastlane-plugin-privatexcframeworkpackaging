require 'fastlane/action'
require_relative '../helper/privatexcframeworkpackaging_helper'

module Fastlane
  module Actions
    class PrivatexcframeworkpackagingAction < Action
      def self.run(params)
        UI.message("The privatexcframeworkpackaging plugin is working!")
      end

      def self.description
        "hoge"
      end

      def self.authors
        ["Masami Yamate"]
      end

      def self.return_value
        # If your method provides a return value, you can describe here what it does
      end

      def self.details
        # Optional:
        "hoge"
      end

      def self.available_options
        [
          # FastlaneCore::ConfigItem.new(key: :your_option,
          #                         env_name: "PRIVATEXCFRAMEWORKPACKAGING_YOUR_OPTION",
          #                      description: "A description of your option",
          #                         optional: false,
          #                             type: String)
        ]
      end

      def self.is_supported?(platform)
        # Adjust this if your plugin only works for a particular platform (iOS vs. Android, for example)
        # See: https://docs.fastlane.tools/advanced/#control-configuration-by-lane-and-by-platform
        #
        # [:ios, :mac, :android].include?(platform)
        true
      end
    end
  end
end
