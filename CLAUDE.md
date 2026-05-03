# AudioCapture

App de menu bar para macOS que captura audio de aplicaciones, graba video + audio de ventanas, o descarga audio desde URLs (YouTube, SoundCloud, etc.).

## Stack

- Swift + SwiftUI (menu bar app)
- ScreenCaptureKit (audio/video desde apps)
- AVFoundation (writing m4a/wav/mp4/mov)
- yt-dlp + deno + ffmpeg (descarga URL — yt-dlp invoca deno para resolver challenges JS y ffmpeg/ffprobe para postprocessing)
- Sin sandbox (`AudioCapture.entitlements`: `app-sandbox=false`) para poder ejecutar herramientas externas desde rutas del sistema.

## Build y deploy

```bash
./build.sh                     # compila, firma ad-hoc, e instala en /Applications
SKIP_INSTALL=1 ./build.sh      # solo compila a build/ (sin tocar /Applications)
```

El script:
1. Compila los `.swift` con `swiftc` (target `arm64-apple-macosx13.0`).
2. Crea el bundle `.app` y lo firma ad-hoc (`codesign --sign -`).
3. Cierra cualquier instancia de AudioCapture corriendo (`pkill -x AudioCapture`).
4. Copia con `ditto` a `/Applications/AudioCapture.app`.

Locaciones donde puede vivir el `.app`:
- `/Applications/AudioCapture.app` — instalación de uso diario (la que el script deja lista)
- `build/AudioCapture.app` — output crudo del build script
- `~/Library/Developer/Xcode/DerivedData/AudioCapture-*/Build/Products/{Debug,Release}/AudioCapture.app` — builds desde Xcode (legacy, no se usa)

## Modos

1. **Audio** — captura audio de una app específica via `SCStream` (AudioRecorder.swift)
2. **Video** — graba ventana + audio en mp4/mov (AudioRecorder.swift, video mode)
3. **URL** — descarga audio desde URL via yt-dlp con fallback a AVPlayer (URLRecorder.swift)

## Dependencias externas (modo URL)

El modo URL requiere tres herramientas en `/usr/local/bin/` o `/opt/homebrew/bin/`:

```bash
brew install yt-dlp deno ffmpeg
```

- **yt-dlp**: descarga.
- **deno**: runtime JavaScript que yt-dlp usa para resolver los challenges de YouTube (signature + n-parameter).
- **ffmpeg / ffprobe**: postprocessing (convertir `.webm`/`.opus` a `.m4a` o `.wav`).

`URLRecorder.ytdlpPath()` busca primero `/usr/local/bin/yt-dlp`, después `/opt/homebrew/bin/yt-dlp`. Si no encuentra, muestra el aviso "yt-dlp no instalado" en el menú URL. `deno` y `ffmpeg` se invocan desde dentro de yt-dlp por nombre, vía PATH — por eso es crítico el `ProcessEnvironment.enrichedPATH()` (ver troubleshooting).

## Troubleshooting modo URL (YouTube principalmente)

**Síntoma**: descarga falla, error críptico en el cuadro rojo, o se queda colgada en "Conectando...".

### Solución dentro de la app

Click en el botón **"Actualizar yt-dlp"** debajo del selector de formato (modo URL). Corre `brew upgrade yt-dlp deno ffmpeg` y muestra spinner + versión final. Sirve cuando YouTube cambia su player y rompe los solvers.

### Solución desde terminal

```bash
brew upgrade yt-dlp deno ffmpeg
```

### Por qué falla

Hay dos clases de fallo posibles:

1. **YouTube cambió el player JS** y `yt-dlp`/`deno` están desactualizados. Solver tira `Cannot read properties of undefined (reading 'origin')`, formatos quedan vacíos. Fix: actualizar.

2. **PATH del .app no incluye `/usr/local/bin`** (clásico problema de apps lanzadas por launchd). yt-dlp arranca por path absoluto pero internamente busca `deno` (challenges JS) y `ffmpeg`/`ffprobe` (postprocessing) por PATH; al no encontrarlos descarga `.webm` pero falla la conversión a `.m4a`, y el código caía a fallback AVPlayer que sobre URLs de YouTube tiraba `"Operation Stopped"` (que no era el error real).

   Desde commit del 2026-05-02 esto está resuelto: `URLRecorder` y `BrewUpdater` setean `proc.environment` con PATH enriquecido vía `ProcessEnvironment.enrichedPATH()` (incluye `/usr/local/bin` y `/opt/homebrew/bin`). Además se agregó `URLRecorder.isWebPageURL()` para no caer al fallback AVPlayer en sitios donde no tiene sentido (youtube, soundcloud, etc.).

### Errores se truncan

Errores en la app (modo URL) se truncan a 300 caracteres en [URLRecorder.swift:101-103](Sources/AudioCapture/Models/URLRecorder.swift) antes de mostrarse en `state.errorMessage`. Para ver el error completo, correr `yt-dlp` desde terminal con la misma URL.

### Historial

- 2026-05-02: yt-dlp 2026.3.13 + deno 2.7.5 fallaban en YouTube → `brew upgrade`. Después salió "Operation Stopped" → causa real era PATH del .app (launchd no incluye `/usr/local/bin`). Fix de código: `ProcessEnvironment.enrichedPATH()` + corrección del catch shadowing en `URLRecorder.record()` + skip AVPlayer fallback para URLs de páginas web. Botón "Actualizar yt-dlp" agregado para futuros breaks de YouTube.

## Archivos clave

- [Sources/AudioCapture/Models/URLRecorder.swift](Sources/AudioCapture/Models/URLRecorder.swift) — descarga via yt-dlp (`downloadWithYtdlp`) y fallback AVPlayer; `isWebPageURL` decide cuándo skipear el fallback
- [Sources/AudioCapture/Models/BrewUpdater.swift](Sources/AudioCapture/Models/BrewUpdater.swift) — corre `brew upgrade yt-dlp deno ffmpeg` con progreso streamed
- [Sources/AudioCapture/Models/AudioRecorder.swift](Sources/AudioCapture/Models/AudioRecorder.swift) — captura audio/video via ScreenCaptureKit
- [Sources/AudioCapture/Utilities/ProcessEnvironment.swift](Sources/AudioCapture/Utilities/ProcessEnvironment.swift) — helper PATH para Process() (agrega `/usr/local/bin` y `/opt/homebrew/bin`)
- [Sources/AudioCapture/Views/MenuBarView.swift](Sources/AudioCapture/Views/MenuBarView.swift) — UI principal del menu bar (incluye botón "Actualizar yt-dlp" en modo URL)
- [Sources/AudioCapture/Models/RecordingState.swift](Sources/AudioCapture/Models/RecordingState.swift) — estado observable
- [build.sh](build.sh) — build script (swiftc + codesign ad-hoc)

## Para retomar
> Última sesión: 2026-05-03

### Lo que se hizo
- **Fix bug modo URL con YouTube** — dos capas: (1) `brew upgrade yt-dlp deno` (versiones viejas no resolvían challenges JS); (2) PATH del .app no incluía `/usr/local/bin` → yt-dlp no encontraba ffmpeg/deno → caía a fallback AVPlayer que tiraba "Operation Stopped". Fix de código: `ProcessEnvironment.enrichedPATH()` aplicado en `URLRecorder` y `BrewUpdater`, corrección del shadowing en el catch de `URLRecorder.record()` (que tragaba el error real de yt-dlp), y `isWebPageURL()` para skipear el fallback AVPlayer en sitios donde no aplica.
- **Botón "Actualizar yt-dlp"** agregado en modo URL — corre `brew upgrade yt-dlp deno ffmpeg` con progreso streamed y muestra la versión final con check verde.
- **`build.sh` ahora auto-instala en `/Applications`** (con `SKIP_INSTALL=1` para saltearlo) — antes había que copiar a mano cada vez.
- **CLAUDE.md** creado y actualizado con troubleshooting permanente.
- **Verificado en vivo**: la URL que falló (`https://www.youtube.com/watch?v=3o2SlgX9BhE`) ahora descarga OK. El botón funcionó (subió ffmpeg de 8.0.1_4 a 8.1_1 en la primera ejecución).

### Próximos pasos inmediatos
Nada urgente. La app está funcional para los tres modos.

### Ideas / mejoras posibles
- Agregar test automatizado para el modo URL (ej. mockear `Process` y verificar que `proc.environment` tiene PATH enriquecido).
- Botón "Mostrar log" que abra los últimos errores de yt-dlp completos en una ventana (hoy se truncan a 300 chars).
- Detectar si Homebrew no está instalado y mostrar instrucción en vez de error críptico al apretar "Actualizar yt-dlp".
