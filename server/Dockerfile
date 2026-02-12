FROM dart:stable

WORKDIR /app

COPY server/main.dart /app/server/main.dart

EXPOSE 8080

ENV PORT=8080

CMD ["dart", "run", "server/main.dart"]
