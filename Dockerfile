# syntax=docker/dockerfile:1.7
FROM gradle:9.4.0-jdk25 AS builder
WORKDIR /app

COPY gradlew gradlew.bat settings.gradle.kts build.gradle.kts ./
COPY gradle ./gradle
RUN chmod +x ./gradlew

COPY src ./src
RUN ./gradlew --no-daemon bootJar -x test

FROM busybox:1.36.1-musl AS busybox

FROM eclipse-temurin:25-jre-jammy
WORKDIR /app

COPY --from=busybox /bin/busybox /bin/busybox
COPY --from=builder /app/build/libs/*.jar app.jar

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD ["/bin/busybox", "wget", "-q", "-T", "5", "-O", "/dev/null", "http://127.0.0.1:8080/actuator/health/readiness"]

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
