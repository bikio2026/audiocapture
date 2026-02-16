import SwiftUI

struct AppPickerView: View {
    @ObservedObject var enumerator: AppEnumerator

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Capturar audio de:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { Task { await enumerator.refreshApps() } }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Actualizar lista de apps")
            }

            if let error = enumerator.errorMessage {
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
                Picker("App", selection: $enumerator.selectedApp) {
                    Text("Seleccionar app...").tag(nil as CaptureApp?)
                    ForEach(enumerator.availableApps) { app in
                        Text(app.name).tag(app as CaptureApp?)
                    }
                }
                .labelsHidden()

                Text("Se captura todo el audio de la app seleccionada")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
