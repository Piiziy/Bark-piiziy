# HomePush 사용 가이드

HomePush는 **URL 하나로 내 iPhone에 알림을 보내는 앱**입니다.
단축어, 홈 자동화, 스크립트, 서버 등 HTTP 요청을 보낼 수 있는 곳이면 어디서든 알림을 보낼 수 있습니다.

```
https://<서버 주소>/<푸시 키>/<제목>/<본문>
```

## 처음 설정

1. **앱 설치**: TestFlight에서 HomePush를 설치하고 알림을 **허용**합니다.
2. **서버 연결**: 앱 **홈** 탭에 기본 서버가 등록돼 있습니다. 화면에 나오는 주소가 내 전용 전송 주소입니다.
   - 서버 주소: `https://homepush-oso7gfd3mq-du.a.run.app`
   - 다른 서버를 쓰려면 홈 오른쪽 위 서버 아이콘 → **서버 목록** → `+` → 주소 입력
3. **푸시 키 확인**: 홈 화면의 예시 URL에서 서버 주소 바로 뒤의 문자열이 내 **푸시 키**입니다. 길게 눌러 복사할 수 있습니다. 이 키를 아는 사람은 누구나 내 폰으로 알림을 보낼 수 있으니 공개하지 마세요.
4. **테스트**: 홈의 **테스트 보내기**를 누르면 바로 알림이 옵니다.

> 지금 서버(Cloud Run)는 **기기 한 대 전용**입니다. 앱을 지웠다 다시 설치하거나 iPhone을 바꾸면
> 앱 **설정 → Device Token**을 눌러 복사한 뒤, GitHub 저장소 Secrets의 `DEVICE_TOKEN`을 새 값으로 바꾸고
> Actions의 **Deploy server to Cloud Run**을 다시 실행하세요.

## 보내는 방법

**가장 간단한 방법 (브라우저 주소창에 붙여넣기)**
```
https://homepush-oso7gfd3mq-du.a.run.app/<푸시키>/현관/문이 열렸어요
```

**값을 함께 보내기 (쿼리)**
```
https://homepush-oso7gfd3mq-du.a.run.app/<푸시키>/현관/문이 열렸어요?group=door&icon=https://example.com/door.png
```

**curl / 서버에서 (JSON)**
```bash
curl -X POST "https://homepush-oso7gfd3mq-du.a.run.app/<푸시키>" \
  -H 'Content-Type: application/json; charset=utf-8' \
  -d '{"title":"현관","body":"택배가 왔어요","group":"door","image":"https://example.com/snap.jpg"}'
```

**iPhone 단축어 / 홈 자동화**
1. 단축어 앱 → 새 단축어 → **URL 내용 가져오기**
2. URL: `https://homepush-oso7gfd3mq-du.a.run.app/<푸시키>`
3. 방법: **POST**, 요청 본문: **JSON** → `title`, `body`, `group` 등 추가
4. 홈 앱 → 자동화 → "문이 열릴 때" 등에서 이 단축어를 실행하도록 연결

## 보낼 수 있는 값

| 값 | 설명 | 예시 |
| --- | --- | --- |
| `title` | 제목 | `현관` |
| `subtitle` | 부제목 | `1층` |
| `body` | 본문 | `문이 열렸어요` |
| `markdown` | 본문 대신 마크다운으로 표시 | `**굵게** 표시` |
| `group` | 알림 묶음. 앱 **구독 그룹** 카드와 기록에 그룹별로 표시 | `door` |
| `icon` | 알림 왼쪽 아이콘 이미지 URL | `https://…/door.png` |
| `image` | 알림에 붙일 이미지 URL | `https://…/snap.jpg` |
| `video` | 알림에 붙일 영상 URL (알림을 길게 눌러 재생) | `https://…/clip.mp4` |
| `url` | 알림을 눌렀을 때 열 주소 | `https://…` |
| `sound` | 알림음 이름 (앱 설정 → 알림음에서 확인) | `bell` |
| `level` | `active`(기본), `timeSensitive`(집중 모드 무시), `passive`(조용히), `critical`(무음 모드 무시) | `timeSensitive` |
| `badge` | 앱 아이콘 배지 숫자 | `1` |
| `call` | `1`이면 30초 동안 반복 재생 | `1` |
| `copy` / `autoCopy` | 복사할 내용 / `1`이면 받자마자 자동 복사 | `123456` |
| `isArchive` | `0`이면 기록에 저장하지 않음 | `0` |

이미지와 영상은 **iPhone이 그 URL에서 직접 받습니다.** 공개 HTTPS 주소여야 하고, 파일이 크면 실패할 수 있습니다(이미지 수 MB, 영상은 짧은 클립 권장).

## 암호화 푸시

본문을 AES로 암호화해서 보내면 서버도 내용을 볼 수 없습니다.
앱 **설정 → 암호화 설정**에서 알고리즘·키·IV를 정한 뒤, 같은 키로 암호화한 내용을 `ciphertext` 값으로 보냅니다.
일반적인 홈 알림에는 필요 없는 기능입니다.

## 내 서버 운영

서버는 Google Cloud Run에서 돌아가며, 저장소의 `server/` 폴더를 고쳐 푸시하면 GitHub Actions가 자동으로 다시 배포합니다.
자세한 내용은 [server/cloudrun/README.ko.md](../server/cloudrun/README.ko.md)를 보세요.

## 자주 묻는 질문

**알림이 안 와요**
- iPhone 설정 → HomePush → 알림이 켜져 있는지, 집중 모드가 아닌지 확인하세요.
- 앱을 다시 설치했다면 Device Token이 바뀌었을 수 있습니다. 위 "처음 설정"의 안내대로 `DEVICE_TOKEN`을 바꿔 주세요.
- TestFlight 앱과 Xcode로 직접 설치한 앱은 서로 다른 APNs 환경을 씁니다. 저장소 Variables의 `APNS_SANDBOX`가 TestFlight일 때 `false`인지 확인하세요.

**이미지나 영상이 안 보여요**
- URL이 `https://`로 시작하고, 로그인 없이 열리는 주소인지 확인하세요.

**그룹 아이콘을 매번 넣기 귀찮아요**
- 서버의 그룹 아이콘 표(`server/cloudrun/group-icons.json`)에 `{"door": {"icon": "https://…"}}`처럼 넣어 두면, 그 그룹으로 보낼 때 아이콘이 자동으로 붙습니다.

## 개인정보

- 서버는 받은 알림을 Apple(APNs)로 전달만 하고 **내용을 저장하지 않습니다.** 요청 기록(시간, 결과)만 Cloud Run 로그에 남습니다.
- 알림 기록은 **내 iPhone 안에만** 저장됩니다.
- 이미지와 영상은 iPhone이 원래 주소에서 직접 내려받습니다.
