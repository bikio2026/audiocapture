import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var state: RecordingState
    @StateObject private var appEnumerator = AppEnumerator()
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var urlRecorder = URLRecorder()
    @StateObject private var brewUpdater = BrewUpdater()

    var body: some View {
        VStack(spacing: 12) {
            Text("AudioCapture")
                .font(.headline)

            // Mode selector
            Picker("Modo", selection: $state.recordingMode) {
                ForEach(RecordingMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(state.isRecording)

            Divider()

            // Source selector depends on mode
            if state.recordingMode == .audio {
                audioModeView
            } else if state.recordingMode == .video {
                videoModeView
            } else {
                urlModeView
            }

            // Timer selector (not for URL mode — yt-dlp downloads aren't live)
            if state.recordingMode != .url {
                VStack(spacing: 6) {
                    Toggle("Timer", isOn: $state.timerEnabled)
                        .font(.caption)

                    if state.timerEnabled {
                        HStack(spacing: 2) {
                            timerField(value: $state.timerHours, label: "h", max: 23)
                            Text(":").font(.caption.monospacedDigit())
                            timerField(value: $state.timerMinutes, label: "m", max: 59)
                            Text(":").font(.caption.monospacedDigit())
                            timerField(value: $state.timerSeconds, label: "s", max: 59)
                        }
                    }
                }
            }

            Divider()

            if state.isRecording && state.recordingMode != .url {
                HStack {
                    RecordingIndicatorView(duration: state.formattedDuration)
                    if let remaining = state.remainingTime {
                        Spacer()
                        Text(remaining)
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.orange)
                    }
                }
            }

            if let status = state.urlStatus {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Record/Stop/Download button
            Button(action: { toggleRecording() }) {
                HStack {
                    if state.recordingMode == .url {
                        Image(systemName: state.isRecording ? "xmark.circle.fill" : "arrow.down.circle")
                            .foregroundColor(state.isRecording ? .red : .primary)
                        Text(state.isRecording ? "Cancelar" : "Descargar")
                    } else {
                        Image(systemName: state.isRecording ? "stop.circle.fill" : "record.circle")
                            .foregroundColor(state.isRecording ? .red : .primary)
                        Text(state.isRecording ? "Detener" : "Grabar")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(state.isRecording ? .red : .accentColor)
            .disabled(!canRecord)

            if let error = state.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let url = state.lastSavedURL {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Button("Mostrar en Finder") {
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }

            Divider()

            Button("Salir de AudioCapture") {
                NSApplication.shared.terminate(nil)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 300)
        .task {
            await appEnumerator.refreshApps()
        }
        .onAppear {
            setupExternalStopHandler()
            setupTimerExpiredHandler()
        }
    }

    // MARK: - Audio mode view

    private var audioModeView: some View {
        VStack(spacing: 8) {
            AppPickerView(enumerator: appEnumerator)
                .disabled(state.isRecording)

            Picker("Formato", selection: $state.selectedAudioFormat) {
                ForEach(AudioFormat.allCases, id: \.self) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .disabled(state.isRecording)
        }
    }

    // MARK: - Video mode view

    private var videoModeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Grabar ventana:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { Task { await appEnumerator.refreshApps() } }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            if let error = appEnumerator.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Abrir Ajustes de Privacidad") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
                .font(.caption)
                .buttonStyle(.borderless)
            } else {
                Picker("Ventana", selection: $appEnumerator.selectedWindow) {
                    Text("Seleccionar ventana...").tag(nil as CaptureWindow?)
                    ForEach(appEnumerator.availableWindows) { window in
                        Text(window.displayName).tag(window as CaptureWindow?)
                    }
                }
                .labelsHidden()
                .disabled(state.isRecording)
            }

            Text("Graba video + audio de la ventana seleccionada. Podés usar la Mac normalmente.")
                .font(.caption2)
                .foregroundColor(.secondary)

            Picker("Formato", selection: $state.selectedVideoFormat) {
                ForEach(VideoFormat.allCases, id: \.self) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .disabled(state.isRecording)
        }
    }

    // MARK: - URL mode view

    private var urlModeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("URL de audio/video:")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("https://youtube.com/watch?v=...", text: $state.urlInput)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .disabled(state.isRecording)

            Text("YouTube, SoundCloud, y más. Descarga el audio sin reproducirlo.")
                .font(.caption2)
                .foregroundColor(.secondary)

            if URLRecorder.ytdlpPath() == nil {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("yt-dlp no instalado. Ejecutá: brew install yt-dlp")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }

            Picker("Formato", selection: $state.selectedAudioFormat) {
                ForEach(AudioFormat.allCases, id: \.self) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .disabled(state.isRecording)

            Divider()

            HStack(spacing: 6) {
                Button(action: { runBrewUpdate() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                        Text("Actualizar yt-dlp")
                            .font(.caption)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(state.brewUpdateStatus != nil || state.isRecording)

                if let status = state.brewUpdateStatus {
                    ProgressView().scaleEffect(0.5)
                    Text(status)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if let v = state.brewUpdateSuccessVersion {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("v\(v)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if let err = state.brewUpdateError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text(err)
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }

                Spacer()
            }
        }
    }

    // MARK: - Timer field

    private func timerField(value: Binding<Int>, label: String, max: Int) -> some View {
        HStack(spacing: 1) {
            TextField("0", text: Binding<String>(
                get: { value.wrappedValue == 0 ? "" : "\(value.wrappedValue)" },
                set: { text in
                    if text.isEmpty {
                        value.wrappedValue = 0
                    } else if let n = Int(text) {
                        value.wrappedValue = min(max, Swift.max(0, n))
                    }
                }
            ))
                .frame(width: 30)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospacedDigit())
                .multilineTextAlignment(.center)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Logic

    private var canRecord: Bool {
        if state.isRecording { return true }
        switch state.recordingMode {
        case .audio:
            return appEnumerator.selectedApp != nil
        case .video:
            return appEnumerator.selectedWindow != nil
        case .url:
            return !state.urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func setupExternalStopHandler() {
        recorder.onStreamStoppedExternally = {
            Task { @MainActor in
                let url = await recorder.forceCleanup()
                state.isRecording = false
                state.stopTimer()
                state.lastSavedURL = url
                if url != nil {
                    state.errorMessage = "Grabación detenida desde macOS. Archivo guardado."
                } else {
                    state.errorMessage = "Grabación detenida desde macOS."
                }
            }
        }
    }

    private func setupTimerExpiredHandler() {
        state.onTimerExpired = { [self] in
            toggleRecording()
        }
    }

    private func runBrewUpdate() {
        Task {
            state.brewUpdateError = nil
            state.brewUpdateSuccessVersion = nil
            state.brewUpdateStatus = "Iniciando..."
            do {
                let version = try await brewUpdater.update(onStatus: { status in
                    Task { @MainActor in state.brewUpdateStatus = status }
                })
                state.brewUpdateStatus = nil
                state.brewUpdateSuccessVersion = version
            } catch {
                state.brewUpdateStatus = nil
                state.brewUpdateError = error.localizedDescription
            }
        }
    }

    private func toggleRecording() {
        Task {
            if state.isRecording {
                if state.recordingMode == .url {
                    urlRecorder.cancel()
                    state.isRecording = false
                    state.urlStatus = nil
                    state.errorMessage = "Descarga cancelada"
                } else {
                    do {
                        let url = try await recorder.stopRecording()
                        state.isRecording = false
                        state.stopTimer()
                        state.lastSavedURL = url
                        state.errorMessage = nil
                    } catch {
                        state.errorMessage = error.localizedDescription
                    }
                }
            } else if state.recordingMode == .url {
                state.lastSavedURL = nil
                state.errorMessage = nil
                state.isRecording = true
                do {
                    let url = try await urlRecorder.record(
                        urlString: state.urlInput,
                        format: state.selectedAudioFormat,
                        onStatus: { status in
                            Task { @MainActor in
                                state.urlStatus = status
                            }
                        }
                    )
                    state.isRecording = false
                    state.urlStatus = nil
                    state.lastSavedURL = url
                } catch {
                    state.isRecording = false
                    state.urlStatus = nil
                    state.errorMessage = error.localizedDescription
                }
            } else if state.recordingMode == .audio {
                guard let app = appEnumerator.selectedApp else { return }
                do {
                    state.lastSavedURL = nil
                    state.errorMessage = nil
                    _ = try await recorder.startRecording(app: app.app, format: state.selectedAudioFormat)
                    state.isRecording = true
                    state.startTimer()
                } catch {
                    state.errorMessage = error.localizedDescription
                }
            } else {
                guard let window = appEnumerator.selectedWindow else { return }
                do {
                    state.lastSavedURL = nil
                    state.errorMessage = nil
                    _ = try await recorder.startVideoRecording(window: window.window, format: state.selectedVideoFormat)
                    state.isRecording = true
                    state.startTimer()
                } catch {
                    state.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
