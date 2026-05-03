# AudioCapture

App de menu bar para macOS con tres modos:

1. **Audio** — capturá el audio de cualquier app del sistema (Spotify, navegador, etc.) sin depender de Loopback ni hardware virtual. Usa ScreenCaptureKit.
2. **Video** — grabá ventana específica + audio en MP4 / MOV. Podés seguir usando la Mac normalmente, sólo se captura la ventana elegida.
3. **URL** — pegá un link de YouTube, SoundCloud, Vimeo, etc. y descarga el audio en M4A o WAV. Usa `yt-dlp` por debajo.

## Requisitos

- macOS 13+
- Apple Silicon (target `arm64-apple-macosx13.0`)
- Para modo URL: Homebrew + `yt-dlp deno ffmpeg`

```bash
brew install yt-dlp deno ffmpeg
```

## Instalación

```bash
git clone https://github.com/bikio2026/audiocapture.git
cd audiocapture
./build.sh
```

`build.sh` compila, firma ad-hoc, e instala en `/Applications/AudioCapture.app`. Para sólo compilar sin instalar: `SKIP_INSTALL=1 ./build.sh`.

La primera vez al abrir, macOS va a pedir permiso de **"Grabación de pantalla y audio del sistema"** en Ajustes → Privacidad y seguridad.

## Uso

Click en el ícono de la onda (`waveform.circle`) en la menu bar → se abre una ventana flotante con los tres modos.

- **Audio / Video**: elegí app o ventana, formato, opcional timer, y dale Grabar.
- **URL**: pegá link y dale Descargar. Si YouTube se rompe (cambian su player JS), usá el botón **"Actualizar yt-dlp"** que corre `brew upgrade yt-dlp deno ffmpeg`.

Los archivos se guardan en `~/Music/AudioCapture/`.

## Documentación interna

Ver [CLAUDE.md](CLAUDE.md) para arquitectura, troubleshooting, y notas de desarrollo.
