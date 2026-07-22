FROM ruby:3.4.10-slim

# Packages needed to build native extensions:
#   - build-essential: compiler toolchain
#   - libpq-dev:       pg gem
#   - libyaml-dev:     psych gem (needs libyaml)
#   - git:             some gems resolve git sources
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
      build-essential \
      libpq-dev \
      libyaml-dev \
      git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install gems first so the layer is cached unless Gemfile changes.
COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

EXPOSE 3000

ENTRYPOINT ["bin/docker-entrypoint.sh"]
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
