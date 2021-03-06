module Refinery
  module Blog
    class Category < ActiveRecord::Base
      extend FriendlyId
      extend Mobility

      translates :title, :slug
      attribute :title
      attribute :slug
      after_save { translations.collect(&:save) }

      friendly_id :title, use: [:slugged, :mobility]

      has_many :categorizations, dependent: :destroy, foreign_key: :blog_category_id
      has_many :posts, through: :categorizations, source: :blog_post

      validates :title, presence: true, uniqueness: true

      def self.by_title(title)
        joins(:translations).find_by(title: title)
      end

      def self.translated
        i18n
      end

      def post_count
        posts.live.with_mobility.count
      end

      # how many items to show per page
      self.per_page = Refinery::Blog.posts_per_page

    end
  end
end
