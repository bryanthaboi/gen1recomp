# gen1recomp multiplayer relay -- the proof-of-concept Orbstack container.
#
# This is deliberately the same shape as ~/dev/loghook/Dockerfile: a single
# dependency-free node script, no build step, no package.json.  server.js only
# uses node's own `net`, `http` and `crypto`, so there is nothing to install.
FROM node:20-alpine

WORKDIR /app

# One file.  Everything the relay needs is in it.
COPY server/server.js ./server.js

# The lobby port (newline-framed JSON, protocol v2) and the small HTTP
# control surface (/health, /players, /rooms).
ENV PORT=7778
ENV HTTP_PORT=7779
ENV BIND=0.0.0.0

# POC behaviour: hand every arrival a `test_<random>` name instead of asking
# them to pick one.  Set RELAY_TEST_NAMES=0 to use the client's own name.
ENV RELAY_TEST_NAMES=1

EXPOSE 7778
EXPOSE 7779

# The relay keeps no state on disk (rooms, seats and resume tokens are all in
# memory), so a read-only root filesystem costs nothing and a stray write
# cannot corrupt the host.
USER node

HEALTHCHECK --interval=30s --timeout=3s --start-period=2s --retries=3 \
  CMD node -e "require('http').get({host:'127.0.0.1',port:process.env.HTTP_PORT,path:'/health'},r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

CMD ["node", "server.js"]
