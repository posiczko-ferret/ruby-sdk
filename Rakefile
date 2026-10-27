require "bundler/audit/task"
require "bundler/gem_tasks"
require "minitest/test_task"
require "rubocop/rake_task"

RuboCop::RakeTask.new(:rubocop) do |t|
  t.options = ["--display-cop-names"]
end

Bundler::Audit::Task.new

namespace :security do
  desc "Update the vulnerability database and audit Gemfile.lock"
  task :audit do
    Rake::Task["bundle:audit:update"].invoke
    Rake::Task["bundle:audit"].invoke
  end
end

Minitest::TestTask.create do |t|
  t.test_globs = ["test/**/*_test.rb"]
  t.warning = false
end

task default: [:rubocop, :test]
