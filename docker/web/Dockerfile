ARG NODE_VERSION=22
ARG NGINX_VERSION=1.27

FROM node:${NODE_VERSION}-alpine AS deps

WORKDIR /src

COPY package.json package-lock.json ./

RUN npm ci --no-audit --no-fund

FROM deps AS build

ARG BUILD_CONFIGURATION=production

COPY . .

RUN npm run build -- --configuration=${BUILD_CONFIGURATION}

FROM nginxinc/nginx-unprivileged:${NGINX_VERSION}-alpine AS final

ARG APP_NAME=web

COPY --chown=nginx:nginx nginx.conf /etc/nginx/conf.d/default.conf

COPY --from=build --chown=nginx:nginx /src/dist/${APP_NAME}/browser /usr/share/nginx/html

USER 101

EXPOSE 8080
