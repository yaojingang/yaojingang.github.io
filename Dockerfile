FROM ruby:3.1-alpine

WORKDIR /srv/jekyll

RUN apk add --no-cache build-base git tzdata \
  && gem install jekyll -v 4.2.2 \
  && gem install jekyll-feed kramdown-parser-gfm webrick

EXPOSE 4000 35729

CMD ["jekyll", "serve", "--host", "0.0.0.0", "--port", "4000", "--watch", "--force_polling", "--livereload", "--livereload-port", "35729", "--config", "_config.yml,_config.local.yml"]
