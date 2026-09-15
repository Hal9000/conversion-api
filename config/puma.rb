# frozen_string_literal: true

environment ENV.fetch("RACK_ENV", "development")
bind "tcp://0.0.0.0:#{ENV.fetch("PORT", "9292")}"
threads_count = Integer(ENV.fetch("PUMA_THREADS", "5"))
threads threads_count, threads_count
