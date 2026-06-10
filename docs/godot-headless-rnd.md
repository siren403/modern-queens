# 클라우드 ARM64 환경에서 헤드리스 Godot 렌더-캡쳐 개발방식 검증 스타터

> GPU 없는 aarch64 리눅스 클라우드 호스트에서, **"렌더 불필요 로직은 순수 헤드리스 / 시각 검증은 가상 디스플레이 + 소프트웨어 렌더로 캡쳐"** 라는 개발방식이 실제로 성립하는지를 단계별 Go/No-Go 게이트로 검증한다.

이 문서는 특정 툴 스택(에이전트 오케스트레이터, 셸 멀티플렉서, 버전 매니저 등)을 전제하지 않는다. 표준 셸 + Godot 바이너리 + GDScript만으로 검증한다. CI 러너든 직접 SSH 세션이든 동일하게 적용된다.

---

## 0. 검증 가설

| # | 가설 | 검증 단계 |
|---|------|-----------|
| H1 | arm64 Godot 바이너리가 이 호스트에서 헤드리스로 기동한다 | Phase 1 |
| H2 | GUI 없이 프로젝트 import와 로직 실행이 가능하다 (렌더 불필요 경로) | Phase 2–3 |
| H3 | GPU 없이도 소프트웨어 렌더 스택(가상 디스플레이 + llvmpipe)이 동작한다 | Phase 4 |
| H4 | 실제 씬을 1프레임 렌더해 **비어있지 않은** PNG로 캡쳐할 수 있다 | Phase 5 |
| H5 | 동일 호스트에서 빌드 타겟(Web/Android)으로 export가 된다 | Phase 6 |
| H6 | 캡쳐 1장 비용(시간)이 워크플로에 쓸 만한 수준이다 | Phase 7 |

각 Phase 끝의 **판정** 항목이 다음 단계 진입 게이트다. No-Go면 그 Phase의 "막혔을 때"를 먼저 해소한다.

---

## 1. 전제 / 환경 가정

- 호스트: aarch64 리눅스 VM, **GPU 없음** (CPU 소프트웨어 렌더 전제)
- 데스크톱 환경 없음 (헤드리스 서버)
- 아웃바운드 네트워크로 Godot 바이너리/패키지 설치 가능
- Godot 4.x (가능하면 4.4+ — 전용 `--import` 플래그 사용 가능)

먼저 환경 사실 확인:

```bash
uname -m            # 기대값: aarch64
cat /etc/os-release # 배포판/버전 확인 (apt/dnf 갈래 결정)
nproc; free -h      # 소프트 렌더는 CPU/메모리에 의존하므로 기록해 둔다
```

---

## 2. 의존성 설치

Debian/Ubuntu 계열:

```bash
sudo apt update
sudo apt install -y \
  xvfb \
  libgl1-mesa-dri mesa-utils \
  libfontconfig1 libxkbcommon0 \
  libxi6 libxrandr2 libxcursor1 libxinerama1
```

RHEL/Oracle Linux 계열은 패키지명만 대체: `xorg-x11-server-Xvfb`, `mesa-dri-drivers`, `mesa-demos`, `fontconfig`, `libxkbcommon` 등.

> `libfontconfig` / `libxkbcommon` 누락은 미니멀 이미지에서 Godot이 조용히 죽는 대표 원인이다. 설치 검증 항목에 고정으로 넣어 둔다.

---

## 3. Godot 바이너리 확보

`godotengine.org` 다운로드에서 **Linux arm64** 빌드를 받는다 (스크립트 자동화 시 SHA 검증 권장). 이후 문서에서는 실행 파일을 `./godot.arm64` 로 가정한다.

```bash
./godot.arm64 --version
```

**판정 (H1 일부):** 버전 문자열이 출력되면 통과.

---

## Phase 1 — 헤드리스 기동

렌더 없이 엔진이 뜨고 정상 종료되는지 확인한다.

```bash
./godot.arm64 --headless --quit
```

**기대:** 라이브러리 로드 에러 없이 즉시 종료.
**막혔을 때:** `cannot open shared object file` → §2의 의존성 재확인.
**판정 (H1):** 에러 없이 종료 → **Go**.

---

## Phase 2 — 프로젝트 import (.godot 생성)

`.godot`(import 캐시)가 없으면 이후 단계가 깨지거나 멈춘다. export/캡쳐 **이전에** 반드시 선행한다.

```bash
# Godot 4.4+
./godot.arm64 --headless --path . --import

# 4.4 미만 폴백
./godot.arm64 --headless --editor --path . --quit
```

**기대:** 프로젝트 루트에 `.godot/` 생성, 리소스 import 로그.
**막혔을 때:** 멈춤/행(hang) → 폴백 명령으로 전환, 그래도 안 되면 Godot 버전 핀 검토.
**판정:** `.godot/`가 생성되고 명령이 종료 → **Go**.

---

## Phase 3 — 로직 경로 검증 (렌더 불필요)

순수 헤드리스에서 스크립트가 실행되는지 확인한다. 이 경로는 GPU/디스플레이가 전혀 필요 없어야 한다.

`res://tools/smoke.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
    print("[smoke] headless logic OK, frame=", Engine.get_process_frames())
    quit()
```

```bash
./godot.arm64 --headless --path . --script res://tools/smoke.gd
```

**기대:** `[smoke] headless logic OK ...` 출력 후 종료.
**판정 (H2):** 출력 확인 → **Go**. (여기까지가 "렌더 없이 되는 일"의 경계다.)

---

## Phase 4 — 소프트웨어 렌더 스택 확인

가상 디스플레이(Xvfb) 위에서 Mesa 소프트웨어 OpenGL(llvmpipe)이 잡히는지 확인한다.

```bash
xvfb-run -a -s "-screen 0 1280x720x24" glxinfo -B
```

**기대 핵심 라인:** Renderer가 `llvmpipe (...)` 로 표시. (`LIBGL_ALWAYS_SOFTWARE=1` 을 앞에 붙여 강제 가능)
**참고:** 소프트웨어 Vulkan(lavapipe)은 비conformant로 알려져 Godot에서 크래시/렌더 깨짐 사례가 있다. **본 검증은 OpenGL(Compatibility) 경로를 표준으로 삼는다.** Vulkan은 검증하지 않는다.
**판정 (H3):** `llvmpipe` 확인 → **Go**.

---

## Phase 5 — 렌더 캡쳐 검증 (핵심)

실제 씬을 가상 디스플레이 + Compatibility 렌더러로 1프레임 그려 PNG로 저장한다.

`res://tools/capture.gd` (Node에 붙인 뒤 `capture.tscn`의 루트로 저장):

```gdscript
extends Node

@export var scene_path: String = "res://scenes/main.tscn"  # 캡쳐 대상
@export var out_path: String   = "user://capture.png"
@export var warmup_frames: int = 5

func _ready() -> void:
    add_child((load(scene_path) as PackedScene).instantiate())
    for _i in warmup_frames:
        await get_tree().process_frame
    await RenderingServer.frame_post_draw
    var img: Image = get_viewport().get_texture().get_image()
    img.save_png(out_path)
    print("[capture] saved -> ", ProjectSettings.globalize_path(out_path))
    get_tree().quit()
```

실행 (`--headless` 를 **붙이지 않는다** — Xvfb가 디스플레이를 제공):

```bash
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
  ./godot.arm64 --rendering-method gl_compatibility \
  --path . res://tools/capture.tscn
```

산출물이 **단색(검정/투명)이 아닌지** 확인한다:

```bash
# user:// 의 실제 경로는 위 print 로그로 확인. 예: ~/.local/share/godot/app_userdata/<프로젝트>/capture.png
ls -l <capture.png 경로>
# ImageMagick이 있으면 표준편차가 0이 아니어야 실제 렌더된 것
identify -verbose <capture.png 경로> | grep -i "standard deviation" || true
```

**기대:** 0바이트가 아니고, 단색이 아닌 이미지.
**막혔을 때:**
- 검정/빈 이미지 → warmup_frames 증가, `frame_post_draw` await 유지 확인, `--rendering-method gl_compatibility` 지정 여부 확인.
- 크래시 → Vulkan으로 떨어진 건 아닌지 로그 확인(반드시 Compatibility 강제).
**판정 (H4):** 비어있지 않은 PNG 생성 → **Go**. ← *이 게이트가 개발방식 성립의 핵심.*

---

## Phase 6 — 빌드 타겟 검증 (선택)

동일 호스트에서 배포 타겟으로 export 되는지 확인한다. (export 템플릿 설치, `export_presets.cfg` 선행 필요)

```bash
# Web — Compatibility(WebGL2) 경로라 Phase 5의 캡쳐 결과와 시각적으로 가장 근접
./godot.arm64 --headless --path . --export-release "Web" build/web/index.html

# Android — JDK 17 + Android SDK cmdline tools + NDK + (릴리스 시) 키스토어 필요
./godot.arm64 --headless --path . --export-release "Android" build/app.apk
```

**기대:** 산출물 생성. Web은 결과물 로딩 검증(셸 템플릿 변수 미치환 이슈가 보고된 바 있으니 산출 후 실제 로드 확인 권장).
**판정 (H5):** 타겟별 산출물 생성·동작 → **Go**.

---

## Phase 7 — 비용(시간) 측정

소프트 렌더는 CPU 바운드라 캡쳐 비용을 반드시 수치화한다.

```bash
for res in 640x360 1280x720; do
  echo "== $res =="
  time LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 ${res}x24" \
    ./godot.arm64 --rendering-method gl_compatibility \
    --path . res://tools/capture.tscn
done
```

**기록:** 해상도별 1장 소요 시간. 워크플로 빈도와 곱해 허용 비용인지 판단한다.
**판정 (H6):** 캡쳐 빈도 × 1장 시간이 감당 가능 → **Go**. 아니면 해상도 축소/캡쳐 빈도 조정.

---

## 검증 결과 기록표

| 가설 | 결과 (Go/No-Go/조건부) | 비고 (수치·에러·우회) |
|------|------------------------|------------------------|
| H1 헤드리스 기동 | | |
| H2 로직 경로 | | |
| H3 소프트 렌더 스택 | | |
| H4 렌더 캡쳐 | | |
| H5 빌드 타겟 | | |
| H6 캡쳐 비용 | | |

---

## 알려진 함정 체크리스트

- [ ] `.godot` 캐시를 export/캡쳐 **이전에** 생성했는가 (Phase 2 선행)
- [ ] 캡쳐 시 `--headless` 를 **빼고** Xvfb로 디스플레이를 줬는가
- [ ] 렌더러를 **`gl_compatibility`(OpenGL/llvmpipe)** 로 강제했는가 — 소프트 Vulkan(lavapipe)은 회피
- [ ] `libfontconfig` / `libxkbcommon` 등 런타임 의존성을 설치·검증했는가
- [ ] Web export 산출물을 실제 로드까지 검증했는가 (셸 변수 미치환 이슈)
- [ ] 캡쳐 결과가 단색/빈 이미지가 아닌지 표준편차로 확인했는가

---

## 결론 분기 (검증 후)

- **H1–H4 모두 Go:** 개발방식 성립. "로직=헤드리스 상시, 시각=Xvfb 캡쳐 온디맨드" 2단 검증 루프를 본격화한다.
- **H4 No-Go / H6 비용 과다:** 시각 회귀를 매 변경마다가 아니라 게이트 시점에만 돌리거나, 캡쳐 해상도를 낮추고 구조 인스펙션(.tscn/노드 트리 검증) 비중을 높인다.
- **H3 No-Go:** 소프트 렌더 스택 문제 — Mesa/llvmpipe 설치와 `LIBGL_ALWAYS_SOFTWARE` 강제부터 재점검한다.
