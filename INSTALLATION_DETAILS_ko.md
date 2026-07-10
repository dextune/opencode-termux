# 설치 세부사항

이 문서는 `install-opencode-termux.sh`가 OpenCode를 Termux `aarch64`에서 실행하기 위해 적용하는 호환성 변경을 설명합니다.

## 버전 상태

- 완료된 대상 버전: `1.17.18`
- npm umbrella 패키지: `opencode-ai@1.17.18`
- npm 플랫폼 바이너리: `opencode-linux-arm64@1.17.18`
- 런타임 대상: Android Termux `aarch64` + Termux glibc

이 인스톨러는 `1.17.18`에서 **freeze**되어 있습니다. `VERSION` 오버라이드도 없고 "latest" 태그를 선택하는 범용 인스톨러 계획도 없습니다. 그 이유는 다음 섹션에서 설명합니다.

## 범위

이 인스톨러는 OpenCode를 다시 빌드하지 않고 OpenCode 소스 코드를 수정하지도 않습니다. 공개 레지스트리에서 공식 npm 패키지를 설치하고 사전 빌드된 플랫폼 바이너리를 복사한 뒤 Termux에 특화된 바이너리 호환성 조정만 적용합니다.

## 1. `os.platform()` / `os.arch()` 문제

OpenCode의 npm umbrella 패키지인 `opencode-ai`에는 올바른 플랫폼 패키지를 선택하는 `postinstall.mjs` 스크립트가 포함되어 있습니다. 관련 코드는 다음과 같습니다:

```js
const platformMap = { darwin: "darwin", linux: "linux", win32: "windows" }
const archMap = { x64: "x64", arm64: "arm64", arm: "arm" }

const platform = platformMap[os.platform()] ?? os.platform()
const arch = archMap[os.arch()] ?? os.arch()
const base = `opencode-${platform}-${arch}`
```

Termux에서는:

- `os.platform()`은 `android`를 반환합니다
- `os.arch()`는 `arm64`를 반환합니다

룩업 테이블에 `android` 키가 없기 때문에 `platformMap[os.platform()]`은 `undefined`이고, 폴백인 `os.platform()`이 `android`을 만듭니다. 따라서 합성된 base는 `opencode-android-arm64`가 되는데, **이 패키지는 npm 레지스트리에 존재하지 않습니다.** 공식 `postinstall`은 다음과 같이 중단됩니다:

```text
It seems your package manager failed to install the right opencode CLI package.
Try manually installing "opencode-android-arm64".
```

이는 `opencode-ai`를 `--force`로 설치하든 그렇지 않든 상관없이 발생합니다. `--force`는 npm 자체의 `EBADPLATFORM` 검사만 우회할 뿐이고, postinstall은 *해결된* 패키지 목록에 대해 실행되며 여전히 Android 바이너리를 찾으려 하기 때문입니다.

이 인스톨러는 `npm install`에 `--ignore-scripts`를 전달하고, 플랫폼 바이너리 복사와 ELF 패치를 직접 수행함으로써 이 문제를 완전히 우회합니다.

## 2. ELF 인터프리터 패치

`node_modules/opencode-linux-arm64/bin/opencode`에 있는 사전 빌드된 바이너리는 표준 Linux 동적 로더를 인터프리터로 갖는 ELF aarch64 실행 파일입니다:

```text
/lib/ld-linux-aarch64.so.1
```

Termux에는 그 경로가 없습니다. 인스톨러는 `glibc-runner`를 통해 `patchelf-glibc`를 사용해 바이너리의 인터프리터를 Termux glibc 로더로 지정합니다:

```text
/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1
```

명령 형태:

```sh
glibc-runner patchelf --set-interpreter \
  /data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1 \
  /data/data/com.termux/files/home/.local/share/opencode/bin/opencode
```

이것은 ELF 메타데이터만 변경합니다. 애플리케이션 로직을 다시 쓰지 않습니다.

## 3. Launcher 래퍼

인스톨러는 launcher를 다음 위치에 씁니다:

```text
/data/data/com.termux/files/usr/bin/opencode
```

래퍼는 glibc 바이너리에 영향을 줄 수 있는 라이브러리 경로 변수를 해제하고 패치된 바이너리를 직접 실행합니다:

```sh
#!/data/data/com.termux/files/usr/bin/sh
unset LD_PRELOAD
unset LD_LIBRARY_PATH
exec /data/data/com.termux/files/home/.local/share/opencode/bin/opencode "$@"
```

패치된 바이너리는 이미 Termux glibc 로더를 ELF 인터프리터로 갖고 있기 때문에, 래퍼는 런타임에 `glibc-runner` 없이 직접 exec 합니다.

## 4. 왜 `--ignore-scripts`인가

`opencode-ai`의 postinstall은 실행이 허용되면 세 가지를 수행합니다:

1. 실행 중인 Node 바이너리에서 `process.platform` / `process.arch`를 확인합니다.
2. `opencode-${platform}-${arch}` 이름의 패키지를 찾습니다.
3. 그 패키지의 `bin/opencode`를 `node_modules/opencode-ai/bin/opencode.exe`로 복사합니다.

Termux에서는 2단계가 항상 `opencode-android-arm64`을 만드는데, 그 패키지는 존재하지 않습니다. 그래서 `postinstall`은 non-zero로 종료되고 (npm 버전에 따라) `bin/opencode.exe`를 `Error: opencode-ai's postinstall script was not run.`을 출력하는 자리표시자 에러 스크립트로 남겨두기도 합니다.

인스톨러는 `npm install`에 `--ignore-scripts`를 전달해 실행한 다음, 복사를 직접 수행합니다 — `node_modules/opencode-linux-arm64/bin/opencode`를 `~/.local/share/opencode/bin/opencode`로 직접 복사합니다. 이렇게 하면 존재하지 않는 Android 패키지와 자리표시자-에러 부작용 모두를 우회합니다.

## 5. 검증 포인트

인스톨러는 다음을 검증합니다:

- Node.js 18 이상 사용 가능 여부
- `glibc-runner`와 `patchelf-glibc` 설치 여부
- `opencode-ai@1.17.18`와 `opencode-linux-arm64@1.17.18`가 전역 npm prefix에 설치되어 있는지
- 플랫폼 패키지의 바이너리가 존재하고 실행 가능한지
- `patchelf --print-interpreter`가 Termux glibc 로더 경로를 보고하는지
- `opencode --version`이 `1.17.18`을 보고하는지

수동 확인:

```sh
command -v opencode
opencode --version
glibc-runner /data/data/com.termux/files/usr/glibc/bin/patchelf \
  --print-interpreter ~/.local/share/opencode/bin/opencode
opencode run "say hi in one short sentence"
```

예상 출력 (마지막 줄은 OpenCode 응답이며, 구성된 provider/model에 따라 달라집니다):

```text
/data/data/com.termux/files/usr/bin/opencode
1.17.18
/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1
Hi.
```

## 6. 업스트림 변경 위험

upstream이 다음을 변경하면 향후 버전에서는 수정이 필요할 수 있습니다:

- npm 패키지 레이아웃 (새 optional dependency, 새 플랫폼 키)
- `postinstall.mjs`의 resolution 로직
- ELF 인터프리터 경로 또는 다른 ELF 필드
- glibc 버전 요구사항
- 플랫폼 패키지 내부 사전 빌드 바이너리의 위치나 이름

`--ignore-scripts` + 수동 복사 패턴이 가장 중요한 트릭입니다. 사전 빌드 바이너리가 `node_modules/opencode-linux-arm64/bin/opencode`에 있고 glibc ELF aarch64 실행 파일인 한, 인스톨러는 계속 작동합니다.

## 7. 버전 freeze 정책

이 레포지토리의 모든 바이트 단위 패치(ELF 인터프리터 경로 문자열, `glibc-loader` 런타임 위치, launcher 내부의 파일 디스크립터 연결 등)가 바이너리의 특정 빌드에 대해 검증되었기 때문에, 이 인스톨러는 의도적으로 단일 릴리스에 freeze됩니다:

- `opencode-ai@1.17.18`
- `opencode-linux-arm64@1.17.18`

스크립트는 `VERSION` 노브를 노출하지 않습니다. 미래의 OpenCode 릴리스가 위 6번에 나열된 포인트 중 어느 하나라도 변경하면, 이 인스톨러는 조용히 실패하거나, 더 나쁘게는 성공한 것처럼 보이지만 실제로는 실행되지 않는 바이너리를 생성할 수 있습니다. 어느 쪽도 허용할 수 없으므로 정책은 다음과 같습니다:

1. 인스톨러는 지원 버전을 `FROZEN_VERSION`으로 하드코딩하며, `VERSION`이 다른 값으로 설정되면 중단합니다.
2. README의 "Change version" 섹션은 새 릴리스에 대해 인스톨러를 재검증·재게시하는 데 필요한 수동 단계를 설명합니다.
3. 그 단계가 새 upstream 버전에 대해 완료될 때까지, Termux에 OpenCode를 설치하는 올바른 방법은 `1.17.18`에 머무르는 것입니다.

이는 Termux glibc 바이너리 자체가 내리는 trade-off와 같습니다: `/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1`에 있는 로더는 새 패키지가 게시될 때마다 모양이 바뀌지 않습니다. 의존성을 고정하고, 경계를 감사한 다음, 결과에 commit하세요.