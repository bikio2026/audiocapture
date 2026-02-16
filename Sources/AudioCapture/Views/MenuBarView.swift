import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var state: RecordingState
    @StateObject private var appEnumerator = AppEnumerator()
    @StateObject private var recorder = AudioRecorder()

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
            } else {
                videoModeView
            }

            Divider()

            if state.isRecording {
                RecordingIndicatorView(duration: state.formattedDuration)
            }

            // Record/Stop button
            Button(action: { toggleRecording() }) {
                HStack {
                    Image(systemName: state.isRecording ? "stop.circle.fill" : "record.circle")
                        .foregroundColor(state.isRecording ? .red : .primary)
                    Text(state.isRecording ? "Detener" : "Grabar")
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

    // MARK: - Logic

    private var canRecord: Bool {
        if state.isRecording { return true }
        if state.recordingMode == .audio {
            return appEnumerator.selectedApp != nil
        } else {
            return appEnumerator.selectedWindow != nil
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

    private func toggleRecording() {
        Task {
            if state.isRecording {
                do {
                    let url = try await recorder.stopRecording()
                    state.isRecording = false
                    state.stopTimer()
                    state.lastSavedURL = url
                    state.errorMessage = nil
                } catch {
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
