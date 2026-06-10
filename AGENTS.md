# modern-queens — Agent Routing

## 프로젝트 개요
퀸즈 계열 로직 퍼즐 게임 프로토타입.
Godot 4.6.3 (aarch64, headless) + GDScript.

## 문서 라우팅

| 작업 | 참조 문서 |
|---|---|
| 환경 구성 · 설치 · Phase 검증 | `docs/env-setup.md` |
| 헤드리스 개발방식 가설 및 근거 | `docs/godot-headless-rnd.md` |

## 환경 제약

- GPU 없음 — 렌더는 반드시 `LIBGL_ALWAYS_SOFTWARE=1` + `--rendering-method gl_compatibility`
- 디스플레이 없음 — 시각 검증 시 `xvfb-run` 필수, `--headless` 플래그와 혼용 불가
- 렌더 불필요 로직은 `godot --headless` 로 직접 실행
- 이미지 검증은 `uv run --with pillow`

## 파일 구조

```
modern-queens/
├─ AGENTS.md
├─ CLAUDE.md
├─ project.godot
├─ docs/
│   ├─ env-setup.md
│   └─ godot-headless-rnd.md
├─ scenes/
│   └─ main.tscn
└─ tools/
    ├─ smoke.gd
    ├─ capture.gd
    └─ capture.tscn
```
