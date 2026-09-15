# frozen_string_literal: true

require "rake/testtask"

namespace :db do
  task :migrate do
    sh "bundle exec ruby db/migrate.rb"
  end
end

Rake::TestTask.new(:test) do |task|
  task.libs << "lib"
  task.pattern = "test/**/*_test.rb"
  task.verbose = true
end

task test: "db:migrate"
