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
                }
            }
            .onAppear {
                if model.isSupported, model.phase == .idle {
                    // Brief delay so RoomCaptureView is in the hierarchy
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        model.start()
                    }
                }
            }
            .onChange(of: model.phase) { newPhase in
                if newPhase == .completed {
                    showSaveSheet = true
                }
            }
            .sheet(isPresented: $showSaveSheet) {
                saveSheet
            }
            .alert("Save failed", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
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

    private var bottomBar: some View {
        VStack(spacing: 12) {
            Text(model.instruction)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: Capsule())

            Group {
                switch model.phase {
                case .scanning:
                    Button {
                        model.stop()
                    } label: {
                        Label("Done scanning", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.37, green: 0.92, blue: 0.83))
                    .foregroundStyle(.black)
                    .controlSize(.large)

                case .processing:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Building LiDAR mesh…")
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

                case .failed(let message):
                    VStack(spacing: 10) {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try again") {
                            model.reset()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                model.start()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                case .completed:
                    Button {
                        showSaveSheet = true
                    } label: {
                        Label("Save room", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                case .idle:
                    Button("Start scan") { model.start() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .padding(.top, 12)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private var saveSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Living room, office…"))
                    TextField("Notes", text: $notes, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Save this environment")
                } footer: {
                    Text("Stored on this iPhone. Reopen anytime to view the mesh or walk in AR.")
                }

                if let room = model.finalRoom {
                    Section("Detected structure") {
                        LabeledContent("Walls", value: "\(room.walls.count)")
                        LabeledContent("Objects", value: "\(room.objects.count)")
                        LabeledContent("Doors", value: "\(room.doors.count)")
                        LabeledContent("Windows", value: "\(room.windows.count)")
                        LabeledContent("Openings", value: "\(room.openings.count)")
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
        ContentUnavailableView {
            Label("LiDAR required", systemImage: "camera.viewfinder")
        } description: {
            Text("RoomPlan needs an iPhone or iPad with a LiDAR scanner. Run on a physical Pro device — not the Simulator.")
        } actions: {
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func save() {
        guard let room = model.finalRoom else { return }
        do {
            _ = try store.saveCapturedRoom(
                room,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: notes,
                previewImage: nil
            )
            didSave = true
            showSaveSheet = false
            model.reset()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
