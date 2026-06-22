FROM nginx:1.27-alpine

RUN rm -rf /usr/share/nginx/html/*
COPY index.html /usr/share/nginx/html/

RUN chown -R nginx:nginx /usr/share/nginx/html

EXPOSE 80
