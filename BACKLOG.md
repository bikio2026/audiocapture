# Backlog — AudioCapture

> Captura agresiva de ideas, mejoras y bugs. Los items nunca se borran, sólo se marcan `[x]` cuando se resuelven.

## Pendientes

### UX

- [ ] Botón "Mostrar log completo" en errores del modo URL (hoy se truncan a 300 chars). Abriría una ventana modal con el stderr completo de yt-dlp.
- [ ] Detectar si Homebrew no está instalado al apretar "Actualizar yt-dlp" y mostrar instrucción amigable en vez de error críptico.
- [ ] Recordar la última URL pegada entre sesiones (UserDefaults).
- [ ] Recordar app/ventana seleccionada por defecto entre sesiones.
- [ ] Mostrar tamaño estimado del audio antes de descargar (yt-dlp `--simulate` + parseo de tamaño).

### Tests

- [ ] Test automatizado para `URLRecorder.downloadWithYtdlp` mockeando `Process` — verificar que `proc.environment` incluye `/usr/local/bin` en el PATH.
- [ ] Test para `URLRecorder.isWebPageURL` — cubrir todos los hosts de la lista + edge cases (subdomains, http vs https, paths complejos).

### Robustez

- [ ] Detectar URLs de playlist y avisar (hoy `--no-playlist` ya las restringe a un video, pero el usuario no se entera).
- [ ] Si `ditto` en `build.sh` falla por permisos en `/Applications`, sugerir alternativa.
- [ ] Si la app está corriendo en otra cuenta de usuario, `pkill -x` no la mata. Detectar y avisar.

### Features posibles

- [ ] Modo "Grabación programada" — agendar grabación a una hora específica (ej: capturar streaming en vivo a las 21:00).
- [ ] Soporte para AAC variable bitrate / opus directo (sin re-encode de webm a m4a si la fuente ya es opus).
- [ ] Atajo de teclado global para iniciar/detener (NSGlobalShortcut).

## Resueltos

- [x] **2026-05-03**: Fix bug modo URL en YouTube — PATH del .app no incluía `/usr/local/bin`, yt-dlp no encontraba ffmpeg/deno.
- [x] **2026-05-03**: Botón "Actualizar yt-dlp" en modo URL.
- [x] **2026-05-03**: `build.sh` auto-instala en `/Applications` (con `SKIP_INSTALL=1` para saltearlo).
- [x] **2026-05-03**: Documentación inicial (CLAUDE.md, README.md, este BACKLOG.md).
