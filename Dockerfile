FROM node:12-alpine
LABEL maintainer "testing"
HEALTHCHECK --intervals=5s \
			--timeout=5s \
			CMD curl -f http://127.0.0.1:8080 || exit 1
EXPOSE 8080