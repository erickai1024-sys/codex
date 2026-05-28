FROM ruby:3.3.6-slim

WORKDIR /app

RUN apt-get update -qq \
  && apt-get install -y --no-install-recommends build-essential \
  && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

EXPOSE 3000

CMD ["sh", "-c", "bundle exec rackup config.ru -p ${PORT:-3000} -o 0.0.0.0"]
