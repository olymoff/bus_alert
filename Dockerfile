FROM ruby:3.2-alpine

WORKDIR /app

RUN apk add --no-cache tzdata
ENV TZ=Asia/Tashkent
ENV PORT=8080

COPY . /app

EXPOSE 8080

CMD ["ruby", "run_bot.rb"]
