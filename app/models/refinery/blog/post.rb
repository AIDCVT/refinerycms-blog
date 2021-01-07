require 'acts-as-taggable-on'

module Refinery
  module Blog
    class Post < ActiveRecord::Base
      extend FriendlyId
      extend Mobility

      translates :title, :body, :custom_url, :custom_teaser, :slug, include: :seo_meta

      attribute :title
      attribute :body
      attribute :custom_url
      attribute :custom_teaser
      attribute :slug
      after_save { translations.collect(&:save) }

      class Translation
        is_seo_meta

        def self.seo_fields
          ::SeoMeta.attributes.keys.map {|a| [a, :"#{a}="]}.flatten
        end
      end

      def validating_source_urls?
        Refinery::Blog.validate_source_url
      end

      friendly_id :title, use: :slugged

      is_seo_meta

      acts_as_taggable

      belongs_to :author, proc { readonly(true) }, class_name: Refinery::Blog.user_class.to_s, foreign_key: :user_id, optional: true

      has_many :comments, dependent: :destroy, foreign_key: :blog_post_id
      has_many :categorizations, dependent: :destroy, foreign_key: :blog_post_id, inverse_of: :blog_post
      has_many :categories, through: :categorizations, source: :blog_category

      validates :title, presence: true, uniqueness: true
      validates :body, presence: true
      validates :published_at, presence: true
      validates :author, presence: true, if: :author_required?
      validates :username, presence: true, unless: :author_required?
      validates :source_url, url: {
        if: :validating_source_urls?,
        update: true,
        allow_nil: true,
        allow_blank: true,
        verify: [:resolve_redirects]
      }

      class Translation
        is_seo_meta
      end

      # Override this to disable required authors
      def author_required?
        Refinery::Blog.user_class.present?
      end

      # Delegate SEO Attributes to globalize translation
      seo_fields = ::SeoMeta.attributes.keys.map {|a| [a, :"#{a}="]}.flatten
      delegate(*(seo_fields << {to: :translation}))

      self.per_page = Refinery::Blog.posts_per_page

      def next
        self.class.next(self)
      end

      def prev
        self.class.previous(self)
      end

      def live?
        !draft && published_at <= Time.now
      end

      def author_username
        author.try(:username) || username
      end

      class << self
        # Wrap up the logic of finding the pages based on the translations table.
        def with_mobility(conditions = {})
          mobility_conditions = { locale: ::Mobility.locale.to_s }.merge(conditions)
          translations_conditions = translations_conditions(mobility_conditions)

          # A join implies readonly which we don't really want.
          Post.i18n.where(mobility_conditions)
              .joins(:translations)
              .where(translations_conditions)
              .readonly(false)
        end

        def translations_conditions(original_conditions)
          translations_conditions = {}
          original_conditions.keys.each do |key|
            if translated_attributes.include? key.to_s
              translations_conditions["#{Post::Translation.table_name}.#{key}"] = original_conditions.delete(key)
            end
          end
          translations_conditions
        end

        def translated_attributes
          translated_attribute_names.map(&:to_s) | %w[locale]
        end

        def by_month(date)
          newest_first.where(published_at: date.beginning_of_month..date.end_of_month)
        end

        def by_year(date)
          newest_first.where(published_at: date.beginning_of_year..date.end_of_year).with_mobility
        end

        def by_title(title)
          joins(:translations).find_by(title: title)
        end

        def newest_first
          order("published_at DESC")
        end

        def published_dates_older_than(date)
          newest_first.published_before(date).select(:published_at).map(&:published_at)
        end

        def recent(count)
          newest_first.live.limit(count)
        end

        def popular(count)
          order("access_count DESC").limit(count).with_mobility
        end

        def previous(item)
          newest_first.published_before(item.published_at).first
        end

        def uncategorized
          newest_first.live.includes(:categories).where(
            Refinery::Blog::Categorization.table_name => {blog_category_id: nil}
          )
        end

        def next(current_record)
          where(arel_table[:published_at].gt(current_record.published_at))
            .where(draft: false)
            .order('published_at ASC').with_mobility.first
        end

        def published_before(date=Time.now)
          where(arel_table[:published_at].lt(date))
            .where(draft: false)
            .with_mobility
        end

        alias_method :live, :published_before

        def comments_allowed?
          Refinery::Setting.find_or_set(:comments_allowed, true, scoping: 'blog')
        end

        def teasers_enabled?
          Refinery::Setting.find_or_set(:teasers_enabled, true, scoping: 'blog')
        end

        def teaser_enabled_toggle!
          currently = Refinery::Setting.find_or_set(:teasers_enabled, true, scoping: 'blog')
          Refinery::Setting.set(:teasers_enabled, value: !currently, scoping: 'blog')
        end
      end

      module ShareThis
        def self.enabled?
          Refinery::Blog.share_this_key != "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
        end
      end

    end
  end
end
