# HomePush 앱 아이콘 레이어 (Icon Composer용)

종 모양 집 아이콘을 Liquid Glass용 레이어로 나눈 파일입니다. 모두 1024×1024 투명 PNG입니다.

| 파일 | 내용 | 위에서부터 순서 |
| --- | --- | --- |
| `3-knob.png` | 흰 문손잡이 | 맨 위 |
| `2-door.png` | 노란 아치형 문 | 가운데 |
| `1-house.png` | 흰 종 모양 집 실루엣 | 맨 아래 |
| 배경 | 단색 `#CACCD0` (연회색) | Icon Composer의 Background 설정 |

`preview-composite.png`는 네 개를 겹쳐 본 평면 미리보기입니다. 원본과 같은지 확인하는 용도입니다.

## Icon Composer에서 만들기
1. Xcode → Open Developer Tool → **Icon Composer**
2. 새 문서를 만들고 `1-house.png`, `2-door.png`, `3-knob.png`를 순서대로 끌어다 놓습니다. 각각 별도 레이어(그룹)로 두면 유리 깊이감이 좋아집니다.
3. 오른쪽 Document에서 **Background**를 단색 `#CACCD0`로 설정합니다.
4. 미리보기에서 Default / Dark / Clear / Tinted를 확인하고, 필요하면 레이어별 Liquid Glass, Shadow, Translucency를 조정합니다.
5. 프로젝트 루트(`bark-piiziy/`)에 **`AppIcon.icon`** 이름으로 저장합니다.

저장한 뒤에는 Claude가 Xcode 프로젝트에 연결합니다.
