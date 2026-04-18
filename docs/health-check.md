# Actuator Health Check

이 문서는 Backend 애플리케이션의 Spring Boot Actuator 기반 헬스체크 사용 방법을 설명합니다.

## 목적

헬스체크는 애플리케이션이 정상적으로 실행 중인지 확인하고, 배포 환경에서 트래픽 라우팅 또는 컨테이너 재시작 판단에 활용하기 위한 엔드포인트입니다.

현재 프로젝트는 Spring Boot Actuator를 사용합니다.

## 설정 위치

헬스체크 설정은 다음 파일에 있습니다.

```text
src/main/resources/application.yaml
```

관련 설정:

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health
  endpoint:
    health:
      probes:
        enabled: true
      show-details: never
```

## 제공 엔드포인트

### 기본 Health Check

```http
GET /actuator/health
```

애플리케이션의 전체 상태를 확인합니다.

정상 응답 예시:

```json
{
  "status": "UP"
}
```

### Liveness Probe

```http
GET /actuator/health/liveness
```

애플리케이션 프로세스가 살아 있는지 확인합니다.

- 실패 시 컨테이너 또는 프로세스를 재시작하는 기준으로 사용할 수 있습니다.

정상 응답 예시:

```json
{
  "status": "UP"
}
```

### Readiness Probe

```http
GET /actuator/health/readiness
```

애플리케이션이 요청을 받을 준비가 되었는지 확인합니다.

- 실패 시 트래픽 라우팅 대상에서 제외하는 기준으로 사용할 수 있습니다.

정상 응답 예시:

```json
{
  "status": "UP"
}
```

## Docker 컨테이너 헬스체크

`Dockerfile`은 컨테이너 내부에서 Actuator readiness 엔드포인트를 조회해 Docker health status를 노출합니다.

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD ["/bin/busybox", "wget", "-q", "-T", "5", "-O", "/dev/null", "http://127.0.0.1:8080/actuator/health/readiness"]
```

이 설정이 적용된 컨테이너는 readiness 응답이 `UP`일 때 `healthy`, 실패가 누적되면 `unhealthy` 상태로 표시됩니다.

## 로컬 확인 방법

애플리케이션 실행 후 다음 명령으로 확인할 수 있습니다.

```bash
curl http://localhost:8080/actuator/health
curl http://localhost:8080/actuator/health/liveness
curl http://localhost:8080/actuator/health/readiness
```

모두 정상이라면 HTTP 200과 함께 `"status":"UP"` 응답이 반환됩니다.

## 테스트

헬스체크 엔드포인트는 다음 테스트 파일에서 검증합니다.

```text
src/test/kotlin/org/prography/samsung/backend/BackendApplicationTests.kt
```

검증 항목:

- `/actuator/health`가 HTTP 200을 반환하는지
- `/actuator/health/liveness`가 HTTP 200을 반환하는지
- `/actuator/health/readiness`가 HTTP 200을 반환하는지
- 각 응답의 `status` 값이 `UP`인지

테스트 실행:

```bash
./gradlew test
```

## 보안/노출 정책

현재 외부로 노출하는 Actuator 엔드포인트는 `health`만 허용합니다.

```yaml
management.endpoints.web.exposure.include: health
```

`env`, `beans`, `metrics` 등 내부 정보를 포함할 수 있는 엔드포인트는 기본적으로 노출하지 않습니다.

또한 `show-details: never` 설정으로 health 응답에 상세 내부 정보가 표시되지 않도록 했습니다.
