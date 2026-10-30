# Servidor do Goblo numa imagem pequena (fase 3, docs/DEPLOY.md). O mundo e os dados do
# jogo vão embutidos no binário; o banco SQLite fica no volume /data.
#
#   docker build -t goblo-server server/
#   docker run -p 8080:8080 -v goblo-dados:/data goblo-server
FROM golang:1.27-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /goblo-server ./cmd/server

FROM alpine:3.22
RUN adduser -D -H goblo && mkdir -p /data && chown goblo /data
COPY --from=build /goblo-server /usr/local/bin/goblo-server
# Base IP → país (opcional): copie data/raw/dbip-country-lite.csv.gz para cá antes do build
# se quiser o país sugerido pelo IP; sem ela, vale o idioma do sistema do jogador.
USER goblo
ENV GOBLO_ADDR=:8080 GOBLO_DB=/data/goblo.db
VOLUME /data
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:8080/health || exit 1
ENTRYPOINT ["/usr/local/bin/goblo-server"]
