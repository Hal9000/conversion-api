FROM ruby:3.2-slim

RUN apt-get update \
    && apt-get install --yes --no-install-recommends build-essential libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set path vendor/bundle \
    && bundle install

COPY . .

ENV RACK_ENV=production
ENV PORT=9292

EXPOSE 9292

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
