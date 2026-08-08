import SwiftUI
import RoomPlan

struct ScanFlowView: View {
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var model = RoomCaptureModel()
    @State private var name: String = ""
    @State private var notes: String = ""
    @State private var saveError: String?
    @State private var didSave = false
    @State private var showSaveSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                if model.isSupported {
                    RoomCaptureRepresentable(model: model)
                        .ignoresSafeArea()
                } else {
                    unsupportedView
                }

                if model.phase == .scanning || model.phase == .processing {
                    VStack(spacing: 8) {
                        liveStatsBar
                        if !model.trackingLabel.isEmpty {
                            Text(model.trackingLabel)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.black.opacity(0.45)))
                        }
                        Spacer()
                    }
                    .padding(.top, 8)
                }

                VStack(spacing: 0) {
                    Spacer()
                    bottomBar
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        model.cancel()
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .onAppear {
                model.refreshSupport()
                if model.isSupported, model.phase == .idle {
                    // Longer delay so representable is on screen with non-zero size
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        model.start()
                    }
                }
            }
            .onDisappear {
                if model.phase == .scanning || model.phase == .processing {
                    model.cancel()
                }
            }
            .onChange(of: model.phase) { _, newPhase in
                if newPhase == .completed {
                    if name.isEmpty { name = defaultScanName() }
                    showSaveSheet = true
                }
            }
            .sheet(isPresented: $showSaveSheet) { saveSheet }
            .alert("Save failed", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var navTitle: String {
        switch model.phase {
        case .scanning: return "Scanning"
        case .processing: return "Processing"
        case .completed: return "Complete"
        case .failed: return "Error"
        case .idle: return "New scan"
        }
    }

    private var liveStatsBar: some View {
        HStack(spacing: 8) {
            statPill("Walls", model.liveWalls)
            statPill("Doors", model.liveDoors)
            statPill("Windows", model.liveWindows)
            statPill("Objects", model.liveObjects)
        }
        .padding(.horizontal, 16)
    }

    private func statPill(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            Text(model.instruction)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !model.tipText.isEmpty {
                Text(model.tipText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            }

            Group {
                switch model.phase {
                case .scanning:
                    Button { model.stop() } label: {
                        Label("Done scanning", systemImage: "checkmark.circle.fill")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.25, green: 0.85, blue: 0.55))
                    .foregroundStyle(.black)
                    .controlSize(.large)

                case .processing:
                    HStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text("Building LiDAR mesh…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

                case .failed(let message):
                    VStack(spacing: 12) {
                        Text(message)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                        Button {
                            model.reset()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                model.start()
                            }
                        } label: {
                            Label("Try again", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.blue)
                        .controlSize(.large)
                    }

                case .completed:
                    Button { showSaveSheet = true } label: {
                        Label("Save room", systemImage: "square.and.arrow.down.fill")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.blue)
                    .controlSize(.large)

                case .idle:
                    Button { model.start() } label: {
                        Label("Start LiDAR scan", systemImage: "camera.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.blue)
                    .controlSize(.large)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .padding(.top, 12)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    private var saveSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
                } header: {
                    Text("Save this environment")
                }
                if let room = model.finalRoom {
                    Section("LiDAR structure") {
                        LabeledContent("Walls", value: "\(room.walls.count)")
                        LabeledContent("Doors", value: "\(room.doors.count)")
                        LabeledContent("Windows", value: "\(room.windows.count)")
                        LabeledContent("Objects", value: "\(room.objects.count)")
                    }
                }
            }
            .navigationTitle("Save scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        showSaveSheet = false
                        model.reset()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(model.finalRoom == nil || didSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }

    private var unsupportedView: some View {
        ZStack {
            AppTheme.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("LiDAR required").font(.title2.weight(.bold))
                Button("Close") { dismiss() }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 40)
            }
        }
    }

    private func save() {
        guard let room = model.finalRoom else { return }
        do {
            _ = try store.saveCapturedRoom(
                room,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: notes,
                previewImage: model.viewController.snapshotThumbnail()
            )
            didSave = true
            showSaveSheet = false
            model.reset()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func defaultScanName() -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return "Room \(f.string(from: Date()))"
    }
}
