# Godot 헤드리스 개발 환경 구성

> aarch64 · Ubuntu 24.04.4 LTS · GPU 없음  
> 검증 가설 상세는 `godot-headless-rnd.md` 참조.

---

## 환경 현황

| 항목 | 값 |
|---|---|
| 아키텍처 | aarch64 |
| OS | Ubuntu 24.04.4 LTS |
| CPU | 4코어 |
| RAM | 23GB |
| 부트볼륨 (`/dev/sda1` → `/`) | 45G, 여유 25G |
| 블록볼륨 (`/dev/sdb` → `/mnt/vol1`) | 100G, 여유 77G |
| GPU | 없음 (소프트웨어 렌더 전제) |

---

## 볼륨 배치

```
/dev/sda1 (부트볼륨 → /)
└─ /usr/local/bin/godot     ← symlink (수 바이트 포인터만)

/dev/sdb (블록볼륨 → /mnt/vol1)
├─ tools/
│   └─ godot/
│       ├─ godot.arm64              ← 엔진 바이너리 (~80MB)
│       └─ export-templates/        ← Phase 6 시 추가 (~700MB)
└─ modern-queens/                   ← 프로젝트 루트
    ├─ .godot/                      ← Phase 3에서 생성 (import 캐시, git 제외)
    ├─ docs/
    ├─ scenes/
    │   └─ main.tscn                ← Phase 5 캡쳐 대상
    └─ tools/
        ├─ smoke.gd                 ← Phase 3 로직 검증
        ├─ capture.gd               ← Phase 5 렌더 캡쳐
        └─ capture.tscn             ← Phase 5 캡쳐 씬
```

**배치 근거:**
- 바이너리 + `.godot/` 캐시 + export 템플릿 합산 ~1GB+ 로 늘어난다. 부트볼륨 여유(25G)는 OS·Docker·기타 서비스 몫으로 남긴다.
- symlink는 수 바이트짜리 포인터. 어떤 쉘·세션·cron·sudo에서도 `godot` 명령이 동일하게 동작한다.

---

## 의존성 현황

| 패키지 | 상태 | 용도 |
|---|---|---|
| `xvfb` | **설치됨** | Phase 5 가상 디스플레이 |
| `libgl1-mesa-dri` (25.2.8) | **설치됨** | llvmpipe 소프트웨어 렌더 |
| `libfontconfig1` | **설치됨** | Godot 런타임 의존성 |
| `libxkbcommon0` | **설치됨** | Godot 런타임 의존성 |
| `libxi6` | **설치됨** | Godot 런타임 의존성 |
| `libxrandr2` | **설치됨** | Godot 런타임 의존성 |
| `libxcursor1` | **설치됨** | Godot 런타임 의존성 |
| `libxinerama1` | **설치됨** | Godot 런타임 의존성 |
| `mesa-utils` | **설치됨** | `glxinfo` (Phase 5) |

---

## Phase 0 — 의존성 설치

누락된 패키지 2개 추가. (`unzip`은 Godot zip 해제에 필요하며 미니멀 이미지에서 누락되는 경우가 있다)

```bash
sudo apt install -y mesa-utils unzip
```

설치 확인:

```bash
which glxinfo && which unzip
# 기대값: 각 바이너리 경로 출력
```

---

## Phase 1 — Godot 바이너리 설치

### 디렉토리 생성

```bash
mkdir -p /mnt/vol1/tools/godot
```

### 다운로드 및 설치

```bash
cd /mnt/vol1/tools/godot

curl -LO https://github.com/godotengine/godot-builds/releases/download/4.6.3-stable/Godot_v4.6.3-stable_linux.arm64.zip
unzip Godot_v4.6.3-stable_linux.arm64.zip
mv Godot_v4.6.3-stable_linux.arm64 godot.arm64
chmod +x godot.arm64
rm Godot_v4.6.3-stable_linux.arm64.zip
```

### symlink 생성

```bash
sudo ln -sf /mnt/vol1/tools/godot/godot.arm64 /usr/local/bin/godot
```

### 설치 확인

```bash
which godot
# 기대값: /usr/local/bin/godot

godot --version
# 기대값: 4.6.3.stable.official.xxxxx
```

**판정:** 버전 문자열 출력 → Go. 라이브러리 누락 에러 시 의존성 재확인.

---

## Phase 2 — 헤드리스 기동 (H1)

렌더 없이 엔진이 뜨고 정상 종료되는지 확인한다.

```bash
godot --headless --quit
```

**기대:** 에러 메시지 없이 즉시 종료. 종료 코드 0.

```bash
echo $?
# 기대값: 0
```

**판정 (H1):** 에러 없이 종료 → Go.  
**막혔을 때:** `cannot open shared object file` → Phase 0 의존성 재확인.

---

## Phase 3 — 프로젝트 초기화 (H2 전제)

`.godot/` import 캐시가 없으면 이후 단계가 깨진다. 캡쳐·export 이전에 반드시 선행한다.

**`--import`는 새 프로젝트를 생성하지 않는다.** 이미 존재하는 `project.godot`을 읽고 리소스 캐시를 생성하는 명령이다. 헤드리스 환경에서는 GUI 없이 새 프로젝트를 스캐폴딩하는 공식 도구가 없으므로 `project.godot`을 직접 작성한다.

### project.godot 포맷 안정성

`config_version=5`는 Godot 4.0~4.6 전체에서 동일하다. 마이너 버전 간 포맷 변화 없음. Godot 4.x 범위 안에서는 버전 업그레이드 시 이 파일을 수정할 필요가 없다. 필수 필드는 `config_version=5` 하나뿐이며 나머지는 모두 선택이다.

### project.godot 작성

```bash
cat > /mnt/vol1/modern-queens/project.godot << 'EOF'
; Engine configuration file.
config_version=5

[application]

config/name="modern-queens"
config/features=PackedStringArray("4.6")
EOF
```

### .godot/ 캐시 생성

```bash
cd /mnt/vol1/modern-queens
godot --headless --path . --import
```

**기대:** 파일 스캔 로그 출력 후 종료.

```bash
ls .godot/
# 기대값: editor/ global_script_class_cache.cfg imported/
```

**`.gitignore` 추가:** `.godot/`는 머신 생성 캐시이므로 커밋하지 않는다.

```bash
echo '.godot/' >> /mnt/vol1/modern-queens/.gitignore
```

**판정:** `.godot/` 생성 후 종료 → Go.

---

## Phase 4 — 로직 경로 검증 (H2)

GPU·디스플레이 없이 GDScript가 실행되는지 확인한다. 이 경로는 렌더가 전혀 개입하지 않는다.

### smoke.gd 작성

```bash
mkdir -p /mnt/vol1/modern-queens/tools

cat > /mnt/vol1/modern-queens/tools/smoke.gd << 'EOF'
extends SceneTree

func _initialize() -> void:
    print("[smoke] headless logic OK, frame=", Engine.get_process_frames())
    quit()
EOF
```

### 실행

```bash
godot --headless --path /mnt/vol1/modern-queens --script res://tools/smoke.gd
```

**기대:**

```
[smoke] headless logic OK, frame=0
```

**판정 (H2):** 위 출력 확인 → Go. 여기까지가 "렌더 없이 되는 일"의 경계다.

---

## Phase 5 — 소프트웨어 렌더 스택 확인 (H3)

Xvfb 가상 디스플레이 위에서 Mesa llvmpipe(CPU 소프트웨어 OpenGL)가 잡히는지 확인한다.

```bash
xvfb-run -a -s "-screen 0 1280x720x24" glxinfo -B
```

**기대 핵심 라인:**

```
OpenGL renderer string: llvmpipe (LLVM 17.x.x, ...)
```

강제 소프트웨어 렌더 확인이 필요하면:

```bash
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" glxinfo -B | grep -i renderer
```

**판정 (H3):** `llvmpipe` 포함 → Go.  
**주의:** 소프트 Vulkan(lavapipe)은 Godot에서 크래시 사례가 있다. 이후 모든 렌더 단계는 OpenGL Compatibility 경로로 강제한다.

---

## Phase 6 — 렌더 캡쳐 (H4) ← 핵심 게이트

실제 씬을 Xvfb + Compatibility 렌더러로 1프레임 그려 PNG로 저장한다. 이 게이트 통과가 개발방식 성립의 기준이다.

### 캡쳐 대상 씬 작성

배경 2색 + 타이틀 텍스트(그림자 포함) + 서브타이틀로 구성. 단색이 아닌 씬이어야 stddev로 실제 렌더 여부를 의미 있게 검증할 수 있다.

```bash
mkdir -p /mnt/vol1/modern-queens/scenes

cat > /mnt/vol1/modern-queens/scenes/main.tscn << 'EOF'
[gd_scene format=3]

[node name="Main" type="Control"]
anchor_right = 1.0
anchor_bottom = 1.0

[node name="Background" type="ColorRect" parent="."]
color = Color(0.06, 0.06, 0.14, 1)
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0

[node name="Accent" type="ColorRect" parent="."]
color = Color(0.18, 0.12, 0.35, 1)
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 0.5

[node name="Title" type="Label" parent="."]
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -300.0
offset_top = -80.0
offset_right = 300.0
offset_bottom = 20.0
text = "Hello World"
horizontal_alignment = 1
theme_override_font_sizes/font_size = 96
theme_override_colors/font_color = Color(1.0, 0.88, 0.2, 1)
theme_override_colors/font_shadow_color = Color(0.8, 0.3, 0.0, 0.9)
theme_override_constants/shadow_offset_x = 5
theme_override_constants/shadow_offset_y = 5

[node name="Subtitle" type="Label" parent="."]
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -300.0
offset_top = 40.0
offset_right = 300.0
offset_bottom = 100.0
text = "modern-queens · headless render test"
horizontal_alignment = 1
theme_override_font_sizes/font_size = 28
theme_override_colors/font_color = Color(0.7, 0.85, 1.0, 0.85)
EOF
```

### capture.gd 작성

```bash
cat > /mnt/vol1/modern-queens/tools/capture.gd << 'EOF'
extends Node

@export var scene_path: String = "res://scenes/main.tscn"
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
EOF
```

### capture.tscn 작성

```bash
cat > /mnt/vol1/modern-queens/tools/capture.tscn << 'EOF'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tools/capture.gd" id="1"]

[node name="Capture" type="Node"]
script = ExtResource("1")
EOF
```

### 실행

`--headless` 를 붙이지 않는다 — Xvfb가 디스플레이를 제공한다.

```bash
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --rendering-method gl_compatibility \
  --path /mnt/vol1/modern-queens res://tools/capture.tscn
```

**기대 출력:**

```
[capture] saved -> /home/ubuntu/.local/share/godot/app_userdata/modern-queens/capture.png
```

### 캡쳐 결과 검증

```bash
# 파일 크기 확인 (0바이트면 렌더 실패)
ls -lh ~/.local/share/godot/app_userdata/modern-queens/capture.png

# 해상도·stddev·영역별 색상 분석 (uv가 Pillow를 임시 환경에서 실행)
uv run --with pillow python3 -c "
from PIL import Image, ImageStat

img = Image.open('/home/ubuntu/.local/share/godot/app_userdata/modern-queens/capture.png')
w, h = img.size
stat = ImageStat.Stat(img)

print('size:', img.size)
print('stddev:', [round(v, 2) for v in stat.stddev])

regions = {
    '상단': img.crop((0, 0, w, h//2)),
    '하단': img.crop((0, h//2, w, h)),
    '중앙': img.crop((w//4, h//3, 3*w//4, 2*h//3)),
}
for name, region in regions.items():
    s = ImageStat.Stat(region)
    print(f'{name} 평균색: {[round(v,1) for v in s.mean[:3]]}')
"
```

**판정 (H4):** 파일 크기 > 0 이고 stddev RGB 모두 > 0 → Go.  
**막혔을 때:**
- 검정/빈 이미지 → `warmup_frames` 값을 10으로 늘린 뒤 재실행
- 크래시 → 로그에서 Vulkan으로 폴백됐는지 확인. `--rendering-method gl_compatibility` 누락 여부 재확인

---

## 검증 결과 기록

| 가설 | 결과 | 비고 |
|---|---|---|
| H1 헤드리스 기동 | Go | exit code 0 |
| H2 로직 경로 | Go | `[smoke] headless logic OK, frame=0` |
| H3 소프트 렌더 스택 | Go | `llvmpipe (LLVM 20.1.2, 128 bits)` |
| H4 렌더 캡쳐 | Go | 1152x648 PNG 4.4KB 생성 확인 |

---

## 전체 흐름 요약

```
Phase 0  sudo apt install mesa-utils
Phase 1  Godot 설치 → /mnt/vol1/tools/godot/godot.arm64
         symlink → /usr/local/bin/godot
Phase 2  godot --headless --quit                          (H1)
Phase 3  godot --headless --path . --import              (.godot/ 생성)
Phase 4  smoke.gd → godot --headless --script            (H2)
Phase 5  glxinfo → llvmpipe 확인                         (H3)
Phase 6  Xvfb + gl_compatibility → capture.png           (H4) ← 핵심 게이트
```

H1–H4 모두 Go → "로직=헤드리스 상시, 시각=Xvfb 캡쳐 온디맨드" 2단 루프로 본격 개발 진입.
