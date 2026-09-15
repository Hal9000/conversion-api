# frozen_string_literal: true

module ConversionApi
  module Catalog
    STANDARD_EVENTS = %w[
      purchase
      page_view
      ad_impression
      add_to_wishlist
      add_to_cart
      viewed_cart
      viewed_item
      begin_checkout
      add_payment_info
      remove_from_cart
      refund
      generate_lead
      qualify_lead
      close_convert_lead
      disqualify_lead
      close_unconvert_lead
      sign_up
      search
      unlock_achievement
      install
      customize_product
      contact
      donate
      find_location
      schedule
      start_trial
      subscribe
      custom
    ].freeze

    ADDITIONAL_EVENTS = %w[
      add_shipping_info
      share
      select_content
      select_item
      select_promotion
      view_item_list
      view_promotion
      view_search_results
      spend_virtual_currency
      earn_virtual_currency
      working_lead
      login
      join_group
      level_up
      post_score
      tutorial_begin
      tutorial_complete
    ].freeze

    EVENT_TYPES = (STANDARD_EVENTS + ADDITIONAL_EVENTS).freeze

    SOURCES = %w[
      email
      website
      app
      phone_call
      chat
      physical_store
      system_generated
      business_messaging
      other
    ].freeze
  end
end
