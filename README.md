# Frequency

Runs as a periodic cron to record recent cycle time metrics to statsd.

## Development

    cp .env.example .env

Update the configuration values in `.env` as appropriate.

    foreman run bundle exec ruby script.rb

...or, using docker:

    hokusai dev start
