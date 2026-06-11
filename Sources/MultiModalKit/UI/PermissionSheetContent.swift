import Foundation
import SwiftUI

@MainActor
struct MultiModalPermissionSheetContent: View {
    let title: LocalizedStringKey
    let completionTitle: LocalizedStringKey
    let states: [MultiModalPermissionState]
    let isAllGranted: Bool
    let requestingPermission: MultiModalPermission?
    let canOpenSettings: Bool
    let onSelect: (MultiModalPermissionState) -> Void
    let onOpenSettings: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(title, bundle: .module)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Image(systemName: isAllGranted ? "person.badge.shield.checkmark" : "person.badge.shield.exclamationmark")
                .font(.system(size: 60))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 100, height: 100)
                .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 30, style: .continuous))

            VStack(alignment: .leading, spacing: 18) {
                ForEach(states) { state in
                    Button {
                        onSelect(state)
                    } label: {
                        MultiModalPermissionSheetRow(
                            state: state,
                            isRequesting: requestingPermission == state.permission
                        )
                    }
                    .buttonStyle(.plain)
                    .permissionSheetRowChrome()
                    .contentShape(Capsule())
                    .disabled(
                        requestingPermission != nil &&
                        requestingPermission != state.permission
                    )
                }
            }
            .padding(.top, 10)

            Spacer(minLength: 0)

            Button(action: onFinish) {
                Text(completionTitle, bundle: .module)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.blue.gradient, in: Capsule())
            }
            .disabled(!isAllGranted)
            .opacity(isAllGranted ? 1 : 0.6)
            .overlay(alignment: .top) {
                if canOpenSettings && !isAllGranted {
                    Button(action: onOpenSettings) {
                        Text("Go to Settings", bundle: .module)
                    }
                        .offset(y: -30)
                }
            }
        }
    }
}

@MainActor
private struct MultiModalPermissionSheetRow: View {
    let state: MultiModalPermissionState
    let isRequesting: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                if isRequesting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: state.status.statusSymbolName)
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(state.status.statusTint)
                }
            }
            .frame(width: 24, height: 24)

            Image(systemName: state.permission.symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Text(state.permission.displayTitle)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private extension MultiModalPermissionStatus {
    var statusSymbolName: String {
        switch self {
        case .authorized, .limited:
            "checkmark.circle.fill"
        case .notDetermined:
            "questionmark.circle.fill"
        case .denied, .restricted, .unavailable:
            "xmark.circle.fill"
        }
    }

    var statusTint: Color {
        switch self {
        case .authorized, .limited:
            .green
        case .notDetermined:
            .gray
        case .denied, .restricted, .unavailable:
            .red
        }
    }
}

private extension View {
    @ViewBuilder
    func permissionSheetRowChrome() -> some View {
        #if os(visionOS)
        background(.regularMaterial, in: Capsule())
        #else
        glassEffect(.regular.interactive(), in: Capsule())
        #endif
    }
}
