# OpenCode for Termux

<p align="center">
  <img src="assets/banner.png" alt="OpenCode for Termux 배너" width="768">
</p>

이 스크립트는 Android Termux 전용입니다. 공식 npm 레지스트리에서 [OpenCode](https://github.com/sst/opencode)를 설치하고 Termux `aarch64`에서 실행하는 데 필요한 호환성 패치를 적용합니다.

## 설치

Termux에서 아래 한 줄 설치 명령을 실행하세요:

```sh
curl -fsSL https://raw.githubusercontent.com/dextune/opencode-termux/main/install-opencode-termux.sh | sh
```

이미 이 레포지토리를 클론한 경우:

```sh
sh ./install-opencode-termux.sh
```

```text
OpenCode for Termux
Compatibility installer for Android/aarch64

Target version : 1.18.2
Platform       : opencode-linux-arm64
Install path   : .../share/opencode/bin/opencode
Launcher       : .../usr/bin/opencode
```

## 버전 상태

이 인스톨러는 **단일 OpenCode 릴리스에 대해 freeze되어 있습니다.** 다음만 지원합니다:

- OpenCode 버전: `1.18.2`
- npm umbrella 패키지: `opencode-ai@1.18.2`
- npm 플랫폼 바이너리: `opencode-linux-arm64@1.18.2`

`VERSION` 환경 변수는 의도적으로 무시됩니다. `VERSION`을 `1.18.2`가 아닌 다른 값으로 설정하면 인스톨러가 중단됩니다. 의도적으로 "Change version" 옵션은 두지 않습니다.

### 왜 freeze인가

OpenCode의 ELF 패치(인터프리터 경로, 파일 디스크립터 연결, 복사 대상 레이아웃)는 이 레포지토리가 검증한 `opencode-linux-arm64@1.18.2` 빌드에 대해서만 적용됩니다. 더 새 것이나 더 오래된 빌드는 다음을 가질 수 있습니다:

- `opencode-ai` 내부에서 더 이상 `opencode-linux-arm64`을 선택하지 않는 `postinstall.mjs`;
- 다른 ELF 레이아웃(인터프리터 경로, 섹션 정렬, dynamic 태그);
- 다른 glibc 요구사항;
- 플랫폼 패키지 내에서 사전 빌드 바이너리의 다른 위치나 이름.

upstream이 새 버전을 릴리스하면, 이 인스톨러를 업데이트하기 전에 이 레포지토리의 모든 패치를 새 빌드에 대해 다시 검증해야 합니다. 그때까지 Termux에 OpenCode를 설치하는 올바른 방법은 이 레포지토리가 테스트한 빌드인 `1.18.2`를 사용하는 것이고, 업그레이드 전에 업데이트된 인스톨러가 공개되기를 기다려야 합니다.

## 이 인스톨러가 하는 일

OpenCode는 npm으로 배포됩니다. umbrella 패키지는 `opencode-ai`이고, 각 지원 플랫폼은 자체 optional dependency 패키지(`opencode-linux-arm64`, `opencode-darwin-x64` 등)를 가집니다. umbrella 패키지의 `postinstall` 스크립트는 Node에서 `os.platform()`과 `os.arch()`를 호출해 `opencode-${platform}-${arch}` 형식의 패키지를 선택합니다.

Termux에서 `os.platform()`은 `linux`가 아니라 `android`를 반환합니다. `opencode-android-arm64` 패키지는 존재하지 않기 때문에 공식 `postinstall`은 `Try manually installing "opencode-android-arm64"`라는 메시지와 함께 중단됩니다. `npm install --force`로 우회하려 해도 공식 `postinstall`이 여전히 Android 패키지를 찾으려다 실패합니다.

이 Termux 인스톨러는 다음과 같은 단계로 이를 우회합니다:

1. 필요한 Termux 패키지를 설치합니다.
2. 기존 opencode 설치(launcher, ELF 바이너리, npm 패키지)를 제거합니다.
3. `opencode-ai@1.18.2`를 `--force --ignore-scripts --os=linux --cpu=arm64`로 설치합니다. `--force`는 npm의 `EBADPLATFORM` 검사를 우회하고, `--ignore-scripts`는 `opencode-android-arm64`를 찾으려 하는 upstream postinstall을 건너뜁니다.
4. 같은 플래그로 `opencode-linux-arm64@1.18.2`를 설치합니다. 이 패키지에 실제 사전 빌드된 ELF 바이너리가 들어 있습니다.
5. 플랫폼 패키지의 ELF 바이너리를 `~/.local/share/opencode/bin/opencode`로 복사합니다.
6. `glibc-runner patchelf`를 사용해 ELF 인터프리터를 `/lib/ld-linux-aarch64.so.1`에서 Termux의 glibc 로더(`/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1`)로 다시 씁니다.
7. `LD_PRELOAD` / `LD_LIBRARY_PATH`를 해제하고 패치된 바이너리를 실행하는 `opencode` launcher를 `/data/data/com.termux/files/usr/bin/opencode`에 설치합니다.
8. `opencode --version`을 실행해 `1.18.2`가 보고되는지 확인합니다.

## 요구사항

- Android with Termux.
- `aarch64` 또는 `arm64` CPU 아키텍처.
- Node.js 18 이상 (인스톨러가 없으면 Termux 패키지에서 `nodejs`를 설치합니다).
- npm 레지스트리에 접근할 수 있는 네트워크.
- Termux 패키지, OpenCode npm 패키지, 플랫폼 바이너리(약 175 MB), 패치된 바이너리를 위한 충분한 저장 공간.

스크립트는 `pkg`를 통해 `curl`, `jq`, `nodejs`, `glibc-runner`, `patchelf-glibc` 등 필요한 패키지 의존성을 직접 설치합니다.

## 인스톨러 출력

인스톨러는 OpenCode 스타일의 터미널 화면과 번호가 매겨진 진행 단계를 표시합니다:

```text
OpenCode for Termux
Compatibility installer for Android/aarch64

Target version : 1.18.2
Platform       : opencode-linux-arm64
Install path   : .../share/opencode/bin/opencode
Launcher       : .../usr/bin/opencode

[01/10] Installing required Termux packages
         done: Required Termux packages are installed.

[10/10] Verifying patched installation
1.18.2
         done: OpenCode 1.18.2 is installed successfully.

Installation complete

OpenCode 1.18.2 has been installed.
Command: opencode
Path   : .../usr/bin/opencode
```

## 설치된 파일

기본 경로:

- Launcher: `/data/data/com.termux/files/usr/bin/opencode`
- 패치된 바이너리: `~/.local/share/opencode/bin/opencode`
- npm 패키지: `node_modules/opencode-ai`와 `node_modules/opencode-linux-arm64` (전역 npm prefix 아래)

기존 launcher나 바이너리가 있으면 인스톨러가 교체하기 전에 타임스탬프가 찍힌 백업을 만듭니다.

## 설치 검증

다음 명령으로 확인하세요:

```sh
command -v opencode
opencode --version
```

예상 출력:

```text
/data/data/com.termux/files/usr/bin/opencode
1.18.2
```

패치된 ELF 인터프리터도 직접 확인할 수 있습니다:

```sh
glibc-runner /data/data/com.termux/files/usr/glibc/bin/patchelf \
  --print-interpreter ~/.local/share/opencode/bin/opencode
```

예상 출력:

```text
/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1
```

원샷 프롬프트 테스트:

```sh
opencode run "say hi in one short sentence"
```

## 제거

Termux에서 아래 한 줄 제거 명령을 실행하세요:

```sh
curl -fsSL https://raw.githubusercontent.com/dextune/opencode-termux/main/uninstall-opencode-termux.sh | sh
```

이미 이 레포지토리를 클론한 경우:

```sh
sh ./uninstall-opencode-termux.sh
```

기본적으로 제거 대상:

- `/data/data/com.termux/files/usr/bin/opencode`
- `~/.local/share/opencode/bin/opencode`
- 전역 npm 패키지 `opencode-ai`와 `opencode-linux-arm64`
- 해당 버전의 타임스탬프 백업들

기본적으로 보존 대상:

- `~/.local/share/opencode` (로그, 세션, repo 캐시)

## 사용자 데이터까지 제거

OpenCode 사용자 데이터까지 함께 지우려면:

```sh
curl -fsSL https://raw.githubusercontent.com/dextune/opencode-termux/main/uninstall-opencode-termux.sh | REMOVE_USER_DATA=1 sh
```

이미 이 레포지토리를 클론한 경우:

```sh
REMOVE_USER_DATA=1 sh ./uninstall-opencode-termux.sh
```

## 버전 변경

이 인스톨러는 버전 변경을 지원하지 않습니다. `VERSION` 환경 변수는 의도적으로 무시됩니다. 다른 OpenCode 릴리스를 설치하려면 다음을 수행해야 합니다:

1. 이 레포지토리의 패치 포인트에 대해 새 upstream 릴리스를 수동으로 검증합니다.
2. `install-opencode-termux.sh`와 `uninstall-opencode-termux.sh` 상단의 `FROZEN_VERSION` 상수를 업데이트합니다.
3. 배너 출력의 `VERSION` 줄과 `README.md` / `README_ko.md`의 버전 상태 섹션을 업데이트합니다.
4. 깨끗한 환경에서 인스톨러를 다시 실행하고 `INSTALLATION_DETAILS.md`에 문서화된 같은 확인 절차가 여전히 통과하는지 확인합니다.

이 작업이 끝날 때까지 `1.18.2`를 고수하세요.

## 패치 세부사항

이 프로젝트는 OpenCode를 다시 빌드하거나 OpenCode 소스 코드를 수정하지 않습니다. 공식 npm 패키지를 다운로드하고 사전 빌드된 플랫폼 바이너리를 복사한 뒤 Termux에 필요한 최소한의 런타임 호환성 변경만 적용합니다.

기술적인 설치/패치 세부사항은 `INSTALLATION_DETAILS.md`를 참고하세요.
