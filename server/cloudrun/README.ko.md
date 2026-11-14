# Google Cloud Run 배포 (serverless 모드)

아이폰 한 대로 혼자 쓸 때 가장 싼 방법입니다. DB 없이 동작하고, 요청이 있을 때만 컨테이너가 켜집니다.
개인 사용량이면 보통 Cloud Run 무료 한도 안에 들어갑니다(가격과 무료 한도는 배포 전에 Google Cloud 가격 페이지에서 확인하세요).

| 항목 | 내용 |
| --- | --- |
| 지원 기기 | **1대** (`DEVICE_TOKEN` 하나). 아이폰을 바꾸거나 앱을 재설치하면 토큰을 다시 넣고 재배포합니다 |
| 주소 | `https://<service>-<hash>.<region>.run.app` (도메인 불필요, HTTPS 자동) |
| 시크릿 | APNs 키, 푸시 키, 디바이스 토큰은 Secret Manager에 저장됩니다. git에는 올라가지 않습니다 |
| 첫 요청 | 잠들어 있으면 1~2초 늦을 수 있습니다 |
| 그룹 아이콘 | `cloudrun/group-icons.json`을 이미지에 포함합니다. 수정 후 재배포하세요(`PUT /group-icons`로 바꾼 값은 재시작 시 사라집니다) |

## 1. 처음 한 번 (직접 하셔야 하는 것)
1. https://console.cloud.google.com 에서 **프로젝트 생성**, **결제 계정 연결**(카드 등록, 무료 한도 안에서는 청구되지 않음)
2. 터미널에서 로그인
   ```bash
   gcloud auth login
   ```
3. Apple Developer → Certificates, IDs & Profiles → **Keys** → `+` → *Apple Push Notifications service (APNs)* 체크 → 생성 후 `.p8` 다운로드. Key ID를 메모합니다.
   `.p8`은 다시 받을 수 없으니 안전한 곳(예: `~/keys/`)에 두세요. 저장소 안에 두지 마세요.

## 2. 설정
```bash
cp server/cloudrun/.env.example server/cloudrun/.env
```
`GCP_PROJECT`, `APNS_KEY_FILE`, `APNS_KEY_ID`를 채웁니다. `DEVICE_TOKEN`은 처음엔 비워 둡니다.

- Xcode로 직접 설치한 앱 → `APNS_SANDBOX=true`
- TestFlight 앱 → `APNS_SANDBOX=false`

## 3. 배포
```bash
server/cloudrun/deploy.sh
```
끝나면 `Server URL`이 출력됩니다.

## 4. 기기 연결
1. 앱 → 설정 → **Device Token**을 눌러 복사 → `.env`의 `DEVICE_TOKEN=`에 붙여넣기
2. 다시 `server/cloudrun/deploy.sh` 실행 (시크릿만 바뀌고 새 리비전이 배포됩니다)
3. 앱 → 서버 목록 → `+` → `Server URL` 입력. 등록되면 앱에 푸시 키가 표시됩니다.

## 5. 테스트
```bash
curl "https://<Server URL>/<푸시키>/제목/본문?group=home"
```

## 이미지·영상·아이콘
서버는 URL만 전달하고, **아이폰이 그 URL에서 직접 내려받습니다.** 그래서 Cloud Run에서도 그대로 됩니다.
```bash
curl "https://<Server URL>/<푸시키>/현관/택배가 왔어요?image=https://example.com/door.jpg&icon=https://example.com/box.png"
```
- 공개 **HTTPS** 주소여야 합니다. 아이폰이 접근할 수 있으면 어디든 괜찮습니다(홈캠 스냅샷 URL, 이미지 호스팅 등).
- 큰 파일은 알림 확장의 시간·메모리 제한 때문에 실패할 수 있습니다. 이미지는 수 MB 이하, 영상은 짧은 클립을 권장합니다.
- 내 파일을 올려 두고 싶다면 Cloud Storage 공개 버킷을 쓰면 됩니다.
  ```bash
  gcloud storage buckets create gs://<고유이름> --location=us-central1 --uniform-bucket-level-access
  gcloud storage buckets add-iam-policy-binding gs://<고유이름> --member=allUsers --role=roles/storage.objectViewer
  gcloud storage cp door.jpg gs://<고유이름>/
  # → https://storage.googleapis.com/<고유이름>/door.jpg
  ```
  공개 버킷이므로 누구나 URL로 볼 수 있습니다. 개인적인 사진은 올리지 마세요.

## 문제 해결
- 로그 보기: `gcloud run services logs read homepush --region asia-northeast3 --project <프로젝트>`
- `BadDeviceToken`: `APNS_SANDBOX` 값이 설치 방식(Xcode/TestFlight)과 맞는지 확인하세요.
- 서버 추가 시 `device token is invalid`: `DEVICE_TOKEN`이 앱에 표시된 값과 같은지 확인하고 재배포하세요.
