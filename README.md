# RouteStory

GPS 이동 경로와 여행 중 사진을 한 편의 여행 기록으로 정리하기 위한 Android 우선 Flutter MVP입니다. 현재 버전은 실제 위치·사진 접근, 백그라운드 기록, 영상 생성, 웹 공유 서버를 실행하지 않습니다.

## 실행

```powershell
C:\src\flutter\bin\flutter.bat pub get
C:\src\flutter\bin\flutter.bat run
```

## 생성한 폴더 구조

```text
lib/
  app/                         앱 루트와 의존성 시작점
  core/
    services/                  위치·미디어의 미래 플랫폼 경계
    theme/                     프리미엄 화이트/오프화이트 테마
    widgets/                   지도 미리보기와 공통 버튼
  features/
    home/presentation/         홈과 최근 여행 카드
    shell/presentation/        하단 네비게이션
    trips/
      application/             Riverpod provider
      data/repositories/       현재 더미 메모리 저장소
      domain/entities/         Trip, GpsPoint, Stop, TripPhoto
      domain/repositories/     저장소 계약
      presentation/            기록, 결과, 여행 목록 화면
```

## 주요 클래스 역할

| 클래스 | 역할 |
| --- | --- |
| `RouteStoryApp` | 앱 테마와 최상위 `ProviderScope`를 적용합니다. |
| `AppShell` | 홈 / 여행 / 설정 하단 네비게이션을 제공합니다. |
| `Trip` 등 엔티티 | 실제 DB와 서비스 구현에 독립적인 여행 데이터 계약입니다. |
| `TripRepository` | 저장소 교체 지점입니다. 현재 `MemoryTripRepository`가 더미 데이터를 제공합니다. |
| `LocationTrackingService` | 향후 foreground/background GPS 플러그인을 연결할 인터페이스입니다. |
| `TravelMediaService` | 사진 메타데이터 조회·연결을 위한 인터페이스입니다. |
| `MapPreview` | 지도 SDK를 교체해 끼울 수 있도록 현재 더미 경로를 표시합니다. |

## 다음 개발 단계

1. Drift 스키마와 `DriftTripRepository`를 추가해 Trip, point, stop, photo를 영속화합니다.
2. 위치 권한과 foreground GPS부터 연결하고, 거리 계산 및 정차 감지를 서비스 계층에 구현합니다.
3. 사진 권한과 EXIF 시간/좌표 매칭을 `TravelMediaService` 구현체로 추가합니다.
4. `MapPreview`를 Google Maps 등의 실제 지도 어댑터로 대체합니다.
5. 기록 종료 후 결과를 DB에서 다시 조회하고, 이후 영상 생성·웹 공유는 별도 API 계층으로 추가합니다.

## 실제 GPS 기능을 붙일 때 수정할 위치

- `lib/core/services/location_tracking_service.dart`: 위치 플러그인 기반 구현 계약입니다.
- `lib/features/trips/application/`: 기록 세션 controller와 거리·정차 계산 상태를 추가합니다.
- `lib/features/trips/data/repositories/`: 메모리 저장소를 Drift/SQLite 구현으로 교체합니다.
- `lib/features/trips/domain/entities/gps_point.dart`: 플랫폼 위치 값을 정규화해 저장합니다.
- `lib/features/trips/presentation/record_trip_screen.dart`: 더미 거리와 타이머를 Riverpod 기록 상태로 바꿉니다.
- `android/app/src/main/AndroidManifest.xml`: 위치 권한 및 실제 백그라운드 요구사항이 확정된 시점에만 추가합니다.

현재 MVP에는 위치 권한을 선언하지 않았습니다. 실제 백그라운드 GPS 정책과 사용자 동의 흐름을 정한 뒤 최소 권한으로 추가하세요.
