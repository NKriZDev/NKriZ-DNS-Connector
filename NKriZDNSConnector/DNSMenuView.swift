import SwiftUI

struct DNSMenuView: View {
    @EnvironmentObject private var viewModel: DNSViewModel

    var body: some View {
        Section {
            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }

        Divider()

        Button {
            viewModel.apply(mode: .automatic)
        } label: {
            modeLabel(.automatic)
        }
        .disabled(viewModel.isApplying)

        Button {
            viewModel.apply(mode: .custom)
        } label: {
            modeLabel(.custom)
        }
        .disabled(viewModel.isApplying)

        Divider()

        Button("Refresh Status") {
            viewModel.refreshStatus()
        }
        .disabled(viewModel.isApplying)

        Divider()

        Button("Refresh IP") {
            viewModel.refreshIP()
        }
        .disabled(viewModel.isRefreshingIP)

        if let output = viewModel.ipRefreshOutput {
            Text(output)
                .font(.caption.monospaced())
                .foregroundStyle(viewModel.ipRefreshOutputIsIP ? Color.primary : Color.red)
                .textSelection(.enabled)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }

        if let error = viewModel.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private func modeLabel(_ mode: DNSMode) -> some View {
        HStack {
            Text(mode.label)
            Spacer()
            if viewModel.activeMode == mode {
                Image(systemName: "checkmark")
            }
        }
    }
}
