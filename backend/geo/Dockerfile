FROM ruby:3.3-alpine
WORKDIR /app
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories \
    && apk --timeout 30 add --no-cache sqlite-libs \
    && apk --timeout 30 add --no-cache --virtual .build-deps build-base sqlite-dev \
    && gem install webrick -v 1.9.1 --no-document \
    && gem install sqlite3 -v 1.7.3 --platform ruby --no-document \
    && apk del .build-deps
COPY backend/geo /app
COPY geo /site/geo
ENV BIND_HOST=0.0.0.0 PORT=4010 APP_ENV=production GEO_CONFIG_FILE=/run/secrets/geo-credentials.json GEO_DATA_DIR=/data GEO_SITE_ROOT=/site
RUN addgroup -g 10001 geo && adduser -D -u 10001 -G geo geo \
    && mkdir /data && chown geo:geo /data
USER geo
EXPOSE 4010
CMD ["ruby", "server.rb"]
