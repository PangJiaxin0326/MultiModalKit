import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@MainActor
extension View {
    /// Presents a required-permissions sheet for the provided MultiModalKit permissions.
    public func multiModalPermissionSheet(
        _ permissions: [MultiModalPermission],
        title: LocalizedStringKey = "Required Permissions",
        completionTitle: LocalizedStringKey = "Start using the App"
    ) -> some View {
        modifier(
            MultiModalPermissionSheetModifier(
                permissions: permissions,
                title: title,
                completionTitle: completionTitle
            )
        )
    }

    /// Presents a required-permissions sheet for the provided MultiModalKit permissions.
    public func permissionSheet(
        _ permissions: [MultiModalPermission],
        title: LocalizedStringKey = "Required Permissions",
        completionTitle: LocalizedStringKey = "Start using the App"
    ) -> some View {
        multiModalPermissionSheet(
            permissions,
            title: title,
            completionTitle: completionTitle
        )
    }
}

@MainActor
private struct MultiModalPermissionSheetModifier: ViewModifier {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private let permissions: [MultiModalPermission]
    private let title: LocalizedStringKey
    private let completionTitle: LocalizedStringKey

    @State private var showSheet = false
    @State private var states: [MultiModalPermissionState]
    @State private var requestingPermission: MultiModalPermission?
    @State private var requestTask: Task<Void, Never>?

    private var isAllGranted: Bool {
        !states.isEmpty && states.allSatisfy(\.status.isGranted)
    }

    private var shouldPresentSheet: Bool {
        !states.isEmpty && !isAllGranted
    }

    private var canOpenSettings: Bool {
        settingsURL != nil && states.contains { $0.status.shouldOpenSettings }
    }

    private var sheetHeight: CGFloat {
        min(max(390, 260 + CGFloat(states.count * 54)), 640)
    }

    private var settingsURL: URL? {
        #if os(macOS)
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")
        #elseif canImport(UIKit)
        URL(string: UIApplication.openSettingsURLString)
        #else
        nil
        #endif
    }

    init(
        permissions: [MultiModalPermission],
        title: LocalizedStringKey,
        completionTitle: LocalizedStringKey
    ) {
        let orderedPermissions = MultiModalPermission.ordered(permissions)
        self.permissions = orderedPermissions
        self.title = title
        self.completionTitle = completionTitle
        self._states = State(initialValue: PermissionCenter.states(for: orderedPermissions))
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showSheet) {
                MultiModalPermissionSheetContent(
                    title: title,
                    completionTitle: completionTitle,
                    states: states,
                    isAllGranted: isAllGranted,
                    requestingPermission: requestingPermission,
                    canOpenSettings: canOpenSettings,
                    onSelect: selectPermission,
                    onOpenSettings: openSettings,
                    onFinish: finish
                )
                .padding(.horizontal, 20)
                .padding(.top, 30)
                .presentationDetents([.height(sheetHeight)])
                .interactiveDismissDisabled(shouldPresentSheet)
            }
            .task(id: permissions) {
                refreshPresentationState()
            }
            .onDisappear {
                requestTask?.cancel()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else {
                    return
                }
                refreshPresentationState()
            }
    }

    private func selectPermission(_ state: MultiModalPermissionState) {
        switch state.status {
        case .notDetermined:
            requestPermission(state.permission)
        case .denied:
            openSettings()
        case .authorized, .limited, .restricted, .unavailable:
            break
        }
    }

    private func requestPermission(_ permission: MultiModalPermission) {
        guard requestingPermission == nil else {
            return
        }

        requestTask?.cancel()
        requestingPermission = permission
        requestTask = Task { @MainActor in
            defer {
                if requestingPermission == permission {
                    requestingPermission = nil
                }
            }

            _ = await PermissionCenter.request(permission)
            guard !Task.isCancelled else {
                return
            }
            refreshPresentationState()
        }
    }

    private func openSettings() {
        guard let settingsURL else {
            return
        }
        openURL(settingsURL)
    }

    private func finish() {
        guard isAllGranted else {
            return
        }
        showSheet = false
    }

    private func refreshPresentationState() {
        states = PermissionCenter.states(for: permissions)
        showSheet = shouldPresentSheet
    }
}
