FROM nginx:stable-alpine
ENV PORT=8080
ENV NGINX_ENVSUBST_FILTER=PORT
COPY deploy/default.conf.template /etc/nginx/templates/default.conf.template
COPY docs/ /usr/share/nginx/html/
RUN sed -i 's/worker_processes  auto;/worker_processes  1;/' /etc/nginx/nginx.conf
EXPOSE 8080
