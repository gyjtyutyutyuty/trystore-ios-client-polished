import SwiftUI
import UniformTypeIdentifiers

struct GameProfile: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let bundleID: String
}

struct ContentView: View {
    private let profiles = [
        GameProfile(
            id: "com.dts.freefiremax",
            name: "Free Fire MAX",
            subtitle: "User-owned profile",
            bundleID: "com.dts.freefiremax"
        ),
        GameProfile(
            id: "com.dts.freefireth",
            name: "Free Fire",
            subtitle: "User-owned profile",
            bundleID: "com.dts.freefireth"
        )
    ]

    @StateObject private var store = ProfileStore()
    @State private var pickerProfileID: String?
    @State private var replacementProfileID: String?
    @State private var notice: Notice?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    artwork
                    header

                    ForEach(profiles) { profile in
                        profileCard(profile)
                    }

                    footer
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: pickerPresented) {
                FolderPicker(
                    onPick: { url in
                        if let profileID = pickerProfileID {
                            store.link(profileID: profileID, url: url)
                        }
                        pickerProfileID = nil
                    },
                    onCancel: { pickerProfileID = nil }
                )
            }
            .alert(item: $notice) { notice in
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    dismissButton: .default(Text("Done"))
                )
            }
        }
        .preferredColorScheme(.dark)
    }

    private var artwork: some View {
        Image("LionTheme")
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .clipped()
            .overlay {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.82)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.orange.opacity(0.55), lineWidth: 1)
            }
    }

    private var header: some View {
        VStack(spacing: 5) {
            Text("JVZTXNX")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .tracking(3)
                .foregroundStyle(.orange)
            Text("COSMETIC CHEST PREVIEW")
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func profileCard(_ profile: GameProfile) -> some View {
        let linked = store.isLinked(profileID: profile.id)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "gamecontroller.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.headline.weight(.bold))
                    Text(profile.bundleID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Circle()
                    .fill(linked ? Color.green : Color.white.opacity(0.25))
                    .frame(width: 9, height: 9)
            }

            Text(linked ? "Documents folder linked" : "No game folder linked")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))

            HStack(spacing: 10) {
                Button {
                    pickerProfileID = profile.id
                } label: {
                    Label(linked ? "Change Folder" : "Choose Folder", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)

                Button {
                    replacementProfileID = profile.id
                    performReplacement(for: profile)
                } label: {
                    Label("Aim Chest", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!linked || replacementProfileID != nil)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        }
    }

    private var footer: some View {
        VStack(spacing: 5) {
            Text("Aim Chest only previews/replaces the supplied cosmetic chest asset.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.55))
            Text("Select an exposed Documents/container folder through Files.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.top, 4)
    }

    private var pickerPresented: Binding<Bool> {
        Binding(
            get: { pickerProfileID != nil },
            set: { if !$0 { pickerProfileID = nil } }
        )
    }

    private func performReplacement(for profile: GameProfile) {
        guard let url = store.url(profileID: profile.id) else {
            replacementProfileID = nil
            notice = Notice(title: "Folder Required", message: "Choose the exposed game Documents/container folder first.")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access { url.stopAccessingSecurityScopedResource() }
                DispatchQueue.main.async { replacementProfileID = nil }
            }

            do {
                let result = try SafeCosmeticReplacementService.replaceChestAsset(in: url)
                DispatchQueue.main.async {
                    notice = Notice(
                        title: "Aim Chest Complete",
                        message: "Replaced the cosmetic asset atomically. Backup: \(result.backupName). Verified bytes: \(result.byteCount)."
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    notice = Notice(title: "Aim Chest Failed", message: error.localizedDescription)
                }
            }
        }
    }
}

struct Notice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        controller.delegate = context.coordinator
        controller.allowsMultipleSelection = false
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: FolderPicker
        init(_ parent: FolderPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                parent.onCancel()
                return
            }
            parent.onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}
