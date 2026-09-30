# ColorCapture

macOS 메뉴바 앱 — **색 추출(스포이드)** + **영역 캡처**를 단축키 하나로.

<img src="Resources/icon_1024.png" width="128" alt="ColorCapture 아이콘">

## 기능

| 기능 | 단축키 | 동작 |
|---|---|---|
| 🎨 색 추출 | `⌃⇧C` (Control+Shift+C) | 돋보기로 화면의 색을 클릭 → HEX 코드(`#FF8800`)를 클립보드에 복사 |
| ✂️ 영역 캡처 | `⌃⇧S` (Control+Shift+S) | 마우스로 드래그해서 영역 캡처 → 클립보드 복사 + `~/Pictures/ColorCapture`에 저장 |

- 메뉴바 아이콘을 누르면 최근 색상 목록(클릭하면 다시 복사), 캡처 폴더 열기, 로그인 시 자동 실행 설정
- 캡처 중 `Esc` = 취소, `스페이스` = 창 하나만 캡처

## 요구 사항

- macOS 13 이상
- Xcode (또는 Swift 툴체인)

## 빌드

```bash
# 앱 만들고 바로 실행 → ~/Applications/ColorCapture.app
./build.sh

# 설치 파일 만들기 → dist/ColorCapture-<버전>.pkg (설치 시 /Applications에 설치)
./make_pkg.sh
```

앱 아이콘을 다시 그리려면:

```bash
swift scripts/make_icon.swift Resources/icon_1024.png
```

## 권한

처음 캡처할 때 **화면 기록** 권한이 필요합니다.
시스템 설정 → 개인정보 보호 및 보안 → 화면 및 시스템 오디오 기록 → ColorCapture 켜기

## 구조

```
Sources/ColorCapture/
  App.swift          앱 시작점 (메뉴바 전용)
  AppDelegate.swift  메뉴, 색 추출, 영역 캡처, 자동 실행
  HotKey.swift       전역 단축키 등록 (Carbon)
  HUD.swift          복사/캡처 완료 알림 창
scripts/
  make_icon.swift    아이콘 그리기
  postinstall        설치 후 앱 자동 실행
```
