# Records cycle time metrics for releases in the last hour. Run like:
#   bundle exec ruby script.rb

require 'octokit'
require 'active_support'
require 'active_support/core_ext/numeric'
require 'active_support/core_ext/time'
require 'datadog/statsd'

config = {
  dd_agent_host: ENV['DD_AGENT_HOST'],
  github_access_token: ENV['GITHUB_ACCESS_TOKEN']
}
puts "Starting script with config #{config.map{|k,v| [k, v&.gsub(/.(?<=.{3})/,'*')].join(':') }.join(', ')}"

statsd = Datadog::Statsd.new(config[:dd_agent_host])
client = Octokit::Client.new(access_token: config[:github_access_token])

def pull_requests_for_release(issue, client)
  query = <<-QUERY
    query {
      node(id: "#{issue.node_id}") {
        ...on PullRequest {
          commits(first: 100) {
            edges {
              node {
                ...on PullRequestCommit {
                  commit {
                    associatedPullRequests(first:1) {
                      edges {
                        node {
                          url
                          createdAt
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  QUERY
  response = client.post '/graphql', { query: query }.to_json
  response.data.node.commits.edges.flat_map{|e| e.node.commit.associatedPullRequests.map{|k,v| v.first.node } }.uniq(&:url)
end

t = 1.hour.ago.utc
query = "org:artsy is:pr is:merged base:release merged:#{t.beginning_of_hour.iso8601}..#{t.end_of_hour.iso8601}"
client.search_issues(query, page: 1, per_page: 100).items.each do |release_pr|
  # record time span between PR open and production release
  pull_requests_for_release(release_pr, client).map do |pr|
    age_s = release_pr.closed_at - Time.parse(pr.createdAt)
    puts "Recording pull request age #{age_s} for pull request #{pr.url} in release #{release_pr.html_url}"
    statsd.timing 'release.pull_request_age', age_s*1000 # milliseconds
  end

  repo = release_pr.repository_url.split('/')[-2..-1].join('/')
  first_commit = client.pull_request_commits(repo, release_pr.number, per_page: 1).first
  next unless first_commit

  cycle_time = release_pr.closed_at - first_commit.commit.author.date
  puts "Recording cycle time #{cycle_time} for release #{release_pr.html_url}"
  statsd.timing 'release.first_commit', cycle_time*1000 # milliseconds
end
