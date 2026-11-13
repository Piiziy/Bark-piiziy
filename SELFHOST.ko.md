# HomePush: 자체 운영 Bark (앱 + 서버)

애플 홈 자동화에서 HTTP 요청 한 번으로 내 아이폰에 푸시를 보내는 시스템입니다.
[Finb/Bark](https://github.com/Finb/Bark)(앱)와 [Finb/bark-server](https://github.com/Finb/bark-server)(서버)를 포크했으며,
두 프로젝트 모두 MIT 라이선스입니다. 원저작자 표기는 각 `LICENSE`에 그대로 남아 있습니다.

| 경로 | 내용 |
| --- | --- |
| `/` | iOS 앱 (Bark 포크) |
| `server/` | bark-server 포크 ([Finb/bark-server@a365aa9](https://github.com/Finb/bark-server/commit/a365aa9ddc9362495efffb3db4358b7c12beb963) 기준) |
| `server/selfhost/` | `docker-compose.yml`, `Caddyfile`, `.env.example`, 아이콘 |
| `scripts/rebrand.sh` | 번들 ID, App Group, 팀, 기본 서버, 앱 이름을 한 번에 바꾸는 스크립트 |

## 원본 대비 추가하거나 바꾼 것

1. **APNs 키 주입**: 원본 서버는 Bark 공식 키(Key ID, Team ID, 토픽)가 소스에 하드코딩돼 있습니다.
   이것을 모두 제거하고 환경변수로 받도록 바꿨습니다(`BARK_APNS_KEY_FILE`, `BARK_APNS_KEY_ID`,
   `BARK_APNS_TEAM_ID`, `BARK_APNS_TOPIC`, `BARK_APNS_SANDBOX`). 원본 저장소에 들어 있던 `.p8`/`.pem`도 지웠습니다.
2. **그룹별 기본 아이콘**: 구독(그룹)마다 다른 이미지를 쓸 수 있습니다. 요청에 `icon`이 없으면
   서버가 `group` 값을 보고 아이콘을 자동으로 붙입니다. 자세한 내용은 [그룹별 아이콘](#그룹별-아이콘)을 보세요.
3. **본문 영상**: `video` 파라미터를 새로 지원합니다(`image`는 원본부터 지원). 자세한 내용은 [이미지와 영상 보내기](#이미지와-영상-보내기)를 보세요.
4. **iOS 리브랜딩**: 번들 ID는 `com.piiziy.homepush`, App Group은 `group.com.piiziy.homepush`,
   기본 서버는 `https://push.example.com`, 앱 이름은 HomePush입니다.
   서명 방식은 Automatic으로 바꿨고, Critical Alerts 권한은 애플의 별도 승인이 필요해서 뺐습니다.

> 지금 값은 모두 자리표시자입니다. 도메인과 번들 ID가 정해지면 아래 명령 한 줄로 바꿉니다.
> ```bash
> scripts/rebrand.sh --bundle-id com.<owner>.homepush --team <TEAM_ID> --server https://push.<도메인> --name HomePush
> ```
> 그런 다음 서버 `.env`의 `BARK_APNS_TOPIC`과 `group-icons.json`의 URL도 같은 값으로 맞춰 주세요.

---

## 1. 준비물

| 항목 | 비고 |
| --- | --- |
| Apple Developer Program | 보유 중 |
| Mac + Xcode | iOS 앱 빌드와 TestFlight 업로드에 필요 |
| VPS 1대 | 1 vCPU / 512MB~1GB RAM이면 충분. Docker 사용 |
| 도메인(서브도메인 1개) | 예: `push.example.com`. HTTPS 인증서는 Caddy가 자동 발급 |

## 2. APNs 키 발급

1. [Apple Developer → Certificates, IDs & Profiles → Keys](https://developer.apple.com/account/resources/authkeys/list)에서 **+** 를 누릅니다.
2. **Apple Push Notifications service (APNs)** 를 체크하고 생성한 뒤 `.p8`을 내려받습니다. **다운로드는 한 번만 됩니다.**
3. **Key ID**(10자)와 **Team ID**(우측 상단 Membership)를 기록해 둡니다.
4. `.p8`은 저장소에 절대 넣지 않습니다. `.gitignore`가 `secrets/`와 `.env`를 막고 있습니다.

## 3. 서버 배포 (VPS)

```bash
# 0) Docker 설치 (Ubuntu 기준)
curl -fsSL https://get.docker.com | sh

# 1) 방화벽: 22(SSH), 80, 443만 엽니다. 8080은 compose에서 외부로 publish하지 않습니다.
sudo ufw allow 22/tcp && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp && sudo ufw allow 443/udp && sudo ufw enable

# 2) 소스 가져오기
git clone https://github.com/Piiziy/bark-piiziy.git && cd bark-piiziy/server/selfhost

# 3) 시크릿
mkdir -p secrets && chmod 700 secrets
# 로컬 PC에서 복사: scp AuthKey_XXXXXXXXXX.p8 vps:~/bark-piiziy/server/selfhost/secrets/apns_key.p8
chmod 600 secrets/apns_key.p8

# 4) 설정
cp .env.example .env && chmod 600 .env
vi .env   # BARK_DOMAIN, ACME_EMAIL, APNs 값, Basic Auth 비밀번호(openssl rand -base64 24)

# 5) 그룹 아이콘 표 (선택)
mkdir -p data && cp group-icons.example.json data/group-icons.json
sed -i 's#push.example.com#push.<내도메인>#g' data/group-icons.json

# 6) DNS: push.<내도메인>의 A 레코드를 VPS IP로 지정합니다(전파된 뒤 실행).
docker compose up -d --build
docker compose logs -f   # "init apns client success (topic=..., host=...)" 확인
```

확인:
```bash
curl https://push.<도메인>/ping                    # {"code":200,"message":"pong",...}
curl -I https://push.<도메인>/icons/house.png      # 200
```

### 보안
- **Basic Auth**: `.env`에 `BARK_SERVER_BASIC_AUTH_USER/PASSWORD`를 넣으면 `/ping`, `/healthz`, `/register`를 뺀 모든 경로에 인증이 걸립니다.
  `/register`는 앱이 기기를 등록할 때 쓰는 경로라 원본 설계 그대로 열어 두었습니다.
- **요청 크기**: Caddy에서 요청 본문을 64KB로 제한합니다.
- **속도 제한**: 공식 Caddy 이미지에는 rate limit 모듈이 없습니다. Basic Auth만으로 부족하다고 느껴지면
  `xcaddy build --with github.com/mholt/caddy-ratelimit`로 만든 이미지를 쓰거나, 앞단에 Cloudflare를 두세요.
  메모리 512MB VPS에서는 xcaddy 빌드가 실패할 수 있으니 로컬에서 빌드해서 push하는 편이 낫습니다.
- `.env`, `secrets/`, `data/`는 권한을 600/700으로 둡니다.

### 서버 운영 절차

| 작업 | 명령 |
| --- | --- |
| 업데이트 | `git pull && docker compose up -d --build` |
| 로그 | `docker compose logs -f bark-server` |
| 백업 | `tar czf ~/homepush-$(date +%F).tgz -C ~/bark-piiziy/server/selfhost data .env secrets` (crontab에 매일 등록 권장. 결과물에 시크릿이 들어 있으니 안전한 곳에 보관) |
| 복원 | 새 VPS에서 3단계까지 진행한 뒤 위 tar를 `server/selfhost`에 풀고 `docker compose up -d --build` |
| **APNs 키 교체** | ① 새 키 발급(계정당 최대 2개라 겹쳐서 운영 가능) → ② `secrets/apns_key.p8` 교체, `.env`의 `BARK_APNS_KEY_ID` 수정 → ③ `docker compose up -d` → ④ 테스트 푸시 확인 → ⑤ 옛 키 Revoke |
| Basic Auth 비밀번호 교체 | `.env` 수정 → `docker compose up -d` → 단축어 헤더도 같이 수정 |

## 4. iOS 앱 빌드 (Mac)

```bash
git clone https://github.com/Piiziy/bark-piiziy.git && cd bark-piiziy
git checkout claude/bark-app-development-n625ef   # 머지 전이라면
scripts/rebrand.sh --team <TEAM_ID> --bundle-id com.<owner>.homepush --server https://push.<도메인>
sudo gem install cocoapods   # 또는 bundle install
pod install
open Bark.xcworkspace        # 반드시 .xcworkspace로 엽니다
```

1. 서명 방식이 Automatic이라, 각 타깃의 **Signing & Capabilities**에서 팀이 맞는지만 확인하면 Xcode가 App ID, App Group, 프로비저닝 프로필을 자동으로 만듭니다.
   대상 타깃: Bark, NotificationServiceExtension, NotificationContentExtension, Widget, BarkWatch, BarkWatch NotificationService
2. Capabilities: Push Notifications, App Groups(`group.<번들ID>`), Time Sensitive Notifications, Communication Notifications(아이콘 표시에 필요)
3. 앱 아이콘: `Bark/Assets.xcassets/AppIcon.appiconset`을 내 이미지(1024×1024 PNG)로 바꿉니다.
4. **APNs 환경 주의**
   - Xcode에서 기기로 바로 설치한 빌드는 **sandbox** APNs를 씁니다. 이때는 서버 `.env`를 `BARK_APNS_SANDBOX=true`로 둡니다.
   - TestFlight 빌드는 **production** APNs를 씁니다. 이때는 `BARK_APNS_SANDBOX=false`입니다.
   - 환경을 바꾸면 기기 토큰도 바뀌니, 앱을 열어 다시 등록해야 합니다.

### TestFlight 배포와 90일 만료 대응
TestFlight 빌드는 업로드 후 **90일이 지나면 만료**됩니다. 만료되기 전에 아래 순서로 다시 올립니다(캘린더에 80일 알림을 걸어 두세요).
1. Xcode에서 Bark 타깃의 Build 번호를 1 올립니다(`CURRENT_PROJECT_VERSION`).
2. 대상 기기를 **Any iOS Device**로 고르고 **Product → Archive**를 실행합니다.
3. Organizer에서 **Distribute App → TestFlight Internal Only → Upload**를 누릅니다.
4. App Store Connect에서 처리가 끝나면 내부 테스터에게 자동으로 배포됩니다. 아이폰의 TestFlight 앱에서 업데이트합니다.
5. device key는 바뀌지 않습니다. 같은 서버, 같은 앱이면 단축어를 고칠 필요가 없습니다.

> 앱스토어 공개 배포는 하지 않습니다(원본과 같은 앱이라 심사에서 거절될 수 있습니다).
> App Store Connect에 앱 레코드를 만드는 일이나 TestFlight 업로드는 직접 진행해 주세요.

## 5. 연동과 검증

1. 앱을 실행하고 알림을 허용하면 서버 목록에 `https://push.<도메인>/<device key>`가 보입니다. 이 키를 복사해 둡니다(문서나 채팅에 평문으로 남기지 마세요).
2. 테스트:
   ```bash
   curl -X POST https://push.<도메인>/push \
     -u 'homepush:<비밀번호>' \
     -H "Content-Type: application/json; charset=utf-8" \
     -d '{"device_key":"<KEY>","title":"우리집 알림","body":"테스트","group":"home","level":"timeSensitive"}'
   ```
3. 확인할 것:
   - [ ] 한글이 깨지지 않는다
   - [ ] `icon`을 빼도 group 아이콘(home → 🏠)이 붙고, `icon`을 넣으면 그 아이콘이 우선한다
   - [ ] 같은 `group`끼리 묶인다
   - [ ] 무음이나 집중 모드에서도 `timeSensitive` 알림이 뜬다(설정 → 알림 → HomePush → 시간 민감 알림 허용)
   - [ ] `image`, `video` 첨부가 보이고 재생된다

## 그룹별 아이콘

`server/selfhost/data/group-icons.json` (`BARK_GROUP_ICONS_FILE`로 경로 변경 가능)
```json
{
  "home":     { "icon": "https://push.example.com/icons/house.png" },
  "security": { "icon": "https://push.example.com/icons/rotating_light.png" },
  "door":     "https://push.example.com/icons/door.png",
  "*":        { "icon": "https://push.example.com/icons/bell.png" }
}
```
- 우선순위: 요청의 `icon` → 표의 `group` 항목 → `"*"` 항목 → 아이콘 없음
- 파일을 고치면 재시작하지 않아도 바로 반영됩니다. JSON이 깨지면 마지막으로 정상이던 표를 계속 씁니다.
- HTTP로도 관리할 수 있습니다. 쓰기는 Basic Auth가 켜져 있을 때만 허용됩니다.
  ```bash
  curl -u homepush:<pw> https://push.<도메인>/group-icons
  curl -u homepush:<pw> -X PUT https://push.<도메인>/group-icons/garage \
       -H 'Content-Type: application/json' -d '{"icon":"https://push.<도메인>/icons/door.png"}'
  curl -u homepush:<pw> -X DELETE https://push.<도메인>/group-icons/garage
  ```
- 아이콘 PNG는 `server/selfhost/icons/`에 넣으면 `https://push.<도메인>/icons/<이름>.png`로 서빙됩니다.
  기본 세트는 house, rotating_light, bust_in_silhouette, door, bell, warning이며 Twemoji(CC-BY 4.0)입니다. 출처는 `icons/ATTRIBUTION.md`에 있습니다.
- 암호화 푸시(`ciphertext`)는 서버가 group을 읽을 수 없어서 적용되지 않습니다.

## 이미지와 영상 보내기

| 파라미터 | 동작 |
| --- | --- |
| `image` | 이미지 URL. 알림 썸네일로 쓰이고, 길게 누르면 크게 보입니다. 앱의 기록에도 남습니다. |
| `video` | 영상 URL(mp4/mov 권장). 길게 눌러 펼치면 자동으로 반복 재생되고, 재생/일시정지 버튼이 있습니다. |
| `image` + `video` | 이미지가 썸네일이 되고, 펼치면 영상이 스트리밍으로 재생됩니다. 가장 빠르고 안정적인 조합입니다. |

- `video`만 보내면 확장이 영상을 내려받아 썸네일을 만듭니다. 이때 영상은 **50MB 이하, 15초 안에 받아질 크기**여야 합니다. 그보다 크면 썸네일 없이 펼쳤을 때 스트리밍만 됩니다.
- 파일을 직접 호스팅하려면 `server/selfhost/media/`에 넣고 `https://push.<도메인>/media/<파일>`로 참조하세요.
  이 경로는 **인증 없이 공개**되므로, 파일 이름은 추측하기 어렵게(예: `uuidgen`) 짓습니다.
- 영상 URL은 앱 기록에는 저장되지 않습니다(원본 메시지 모델에 영상 필드가 없음).

```bash
curl -X POST https://push.<도메인>/push -u 'homepush:<pw>' \
  -H "Content-Type: application/json; charset=utf-8" \
  -d '{"device_key":"<KEY>","title":"현관","body":"움직임 감지","group":"door",
       "image":"https://push.<도메인>/media/3f1c….jpg",
       "video":"https://push.<도메인>/media/3f1c….mp4"}'
```

## 6. 애플 홈 자동화용 단축어 설정값

홈 앱에서 **자동화 → (트리거) → 단축어 → URL 콘텐츠 가져오기**를 추가하고 아래처럼 채웁니다.

| 항목 | 값 |
| --- | --- |
| URL | `https://push.<도메인>/push` |
| 메서드 | `POST` |
| 헤더 | `Authorization` = `Basic <base64>` (Basic Auth를 켰을 때) |
| 요청 본문 | `JSON` |
| `device_key` | (텍스트) 앱에서 복사한 키 |
| `title` | (텍스트) 예: `우리집 알림` |
| `body` | (텍스트) 예: `현관문이 열렸습니다` |
| `group` | (텍스트) `home` / `door` / `security` … (아이콘이 자동으로 붙음) |
| `icon` | (선택) 그룹 아이콘 대신 쓸 URL |
| `level` | (텍스트) `timeSensitive` / `active` / `passive` |
| `image`, `video` | (선택) 미디어 URL |

`<base64>` 만들기 (Mac 터미널): `printf 'homepush:<비밀번호>' | base64`
결과가 `aG9tZXB1c2g6…` 같은 문자열이면 헤더 값은 `Basic aG9tZXB1c2g6…`입니다.

## 7. 월 예상 비용

| 항목 | 비용 | 비고 |
| --- | --- | --- |
| Apple Developer Program | 이미 보유 (연 $99) | 추가 비용 없음 |
| VPS | **$0 ~ 약 $5/월** | Oracle Cloud Always Free는 $0. AWS Lightsail, Vultr, Hetzner 등의 최소 플랜은 약 $3.5~5 |
| 도메인 | 약 $1/월 (연 $10~15) | 이미 가진 도메인의 서브도메인을 쓰면 $0 |
| TLS 인증서 | $0 | Let's Encrypt (Caddy 자동 갱신) |
| APNs | $0 | |
| **합계** | **월 $0 ~ 약 $6** | 가격은 작성 시점 기준이니 가입 전에 각 제공자 페이지에서 확인하세요 |

리소스 사용량: bark-server는 메모리 약 10~30MB, Caddy는 약 20~40MB입니다. compose에서 각각 128MB로 제한했습니다.
