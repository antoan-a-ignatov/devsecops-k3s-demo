FROM nginx:1.27-alpine

# Pull latest Alpine security patches for OS packages (openssl, libxml2, etc.)
# nginx:1.27-alpine is a published image that doesn't auto-update its bundled
# packages, so we explicitly upgrade here to pick up fixes published since
# this tag was last built.
RUN apk update && apk upgrade --no-cache

RUN rm -rf /usr/share/nginx/html/*
COPY index.html /usr/share/nginx/html/

RUN chown -R nginx:nginx /usr/share/nginx/html

EXPOSE 80
