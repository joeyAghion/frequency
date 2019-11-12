# Records cycle time metrics for releases in the last hour. Run like:
#   bundle exec ruby script.rb

require 'octokit'
require 'active_support'
require 'active_support/core_ext/numeric'
require 'datadog/statsd'

statsd = Datadog::Statsd.new(ENV['DD_AGENT_HOST'])
client = Octokit::Client.new(access_token: ENV['GITHUB_ACCESS_TOKEN'])

t = 1.hour.ago.utc
query = "org:artsy is:pr is:merged base:release merged:#{t.beginning_of_hour.iso8601}..#{t.end_of_hour.iso8601}"
client.search_issues(query, page: 1, per_page: 100).items.each do |pr|
  repo = pr.repository_url.split('/')[-2..-1].join('/')
  first_commit = client.pull_request_commits(repo, pr.number, per_page: 1).first
  next unless first_commit

  cycle_time = pr.closed_at - first_commit.commit.author.date
  puts "Recording cycle time #{cycle_time} for release #{pr.html_url}"
  #statsd.timing 'release.first_commit', cycle_time*1000 # milliseconds
end
