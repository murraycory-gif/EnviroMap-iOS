import SwiftUI
import RealityKit
import ARKit

struct ARWalkView: View {
    let usdzURL: URL
    @State private var errorText: String?

    var body: some View {
        ZStack {
            ARWalkRepresentable(usdzURL: usdzURL) { err in
                errorText = err
            }
            .ignoresSafeArea()

            VStack {
                Text("Point at the floor, then walk slowly")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 12)
                Spacer()
            }

            if let errorText {
                ContentUnavailableView(
                    "AR walk unavailable",
                    systemImage: "arkit",
                    description: Text(errorText)
                )
                .background(.black.opacity(0.6))
            }
        }
        .navigationTitle("Walk scan")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ARWalkRepresentable: UIViewRepresentable {
    let usdzURL: URL
    var onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(usdzURL: usdzURL, onError: onError)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        context.coordinator.arView = arView

        guard ARWorldTrackingConfiguration.isSupported else {
            DispatchQueue.main.async {
                onError("World tracking is not supported on this device.")
            }
            return arView
        }

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        arView.session.delegate = context.coordinator
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        let coaching = ARCoachingOverlayView()
        coaching.session = arView.session
        coaching.goal = .horizontalPlane
        coaching.activatesAutomatically = true
        coaching.translatesAutoresizingMaskIntoConstraints = false
        arView.addSubview(coaching)
        NSLayoutConstraint.activate([
            coaching.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
            coaching.trailingAnchor.constraint(equalTo: arView.trailingAnchor),
            coaching.topAnchor.constraint(equalTo: arView.topAnchor),
            coaching.bottomAnchor.constraint(equalTo: arView.bottomAnchor),
        ])

        context.coordinator.loadMesh()
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        let usdzURL: URL
        var onError: (String) -> Void
        weak var arView: ARView?
        private var meshEntity: Entity?
        private var didPlace = false

        init(usdzURL: URL, onError: @escaping (String) -> Void) {
            self.usdzURL = usdzURL
            self.onError = onError
            super.init()
        }

        func loadMesh() {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                do {
                    // Synchronous load — works on iOS 17 without async Entity API issues
                    let entity = try Entity.load(contentsOf: self.usdzURL)
                    entity.generateCollisionShapes(recursive: true)
                    DispatchQueue.main.async {
                        self.meshEntity = entity
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.onError(error.localizedDescription)
                    }
                }
            }
        }

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            guard !didPlace, let meshEntity, let arView else { return }
            guard let plane = anchors.compactMap({ $0 as? ARPlaneAnchor }).first else { return }

            didPlace = true
            let anchorEntity = AnchorEntity(anchor: plane)
            let clone = meshEntity.clone(recursive: true)
            clone.position = .zero
            anchorEntity.addChild(clone)
            arView.scene.addAnchor(anchorEntity)
        }
    }
}
