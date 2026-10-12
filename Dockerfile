FROM nginx:stable-alpine
ENV PORT=8080
ENV NGINX_ENVSUBST_FILTER=PORT
COPY deploy/default.conf.template /etc/nginx/templates/default.conf.template
COPY docs/ /usr/share/nginx/html/
RUN sed -i 's/worker_processes  auto;/worker_processes  1;/' /etc/nginx/nginx.conf \
    && find /usr/share/nginx/html -type d -exec chmod 755 {} + \
    && find /usr/share/nginx/html -type f -exec chmod 644 {} + \
    && chmod 644 /etc/nginx/templates/default.conf.template
EXPOSE 8080
