import SwiftUI
import UniformTypeIdentifiers

@main
struct FF7FLACConverterApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ImportedPSF: Identifiable {
    let id = UUID()
    let filename: String
    let source: URL?
    let metadata: PSFTrackMetadata?
    let problem: String?
    let missingLibraries: [String]
}

struct ExportSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ContentView: View {
    @State private var showingImporter = false
    @State private var showingExport = false
    @State private var tracks: [ImportedPSF] = []
    @State private var outputs: [URL] = []
    @State private var converting = false
    @State private var status = "Import .minipsf tracks and their .psflib files together."
    private var ready: [ImportedPSF] {
        tracks.filter { $0.source != nil && $0.problem == nil &&
            $0.missingLibraries.isEmpty && ($0.metadata?.totalSeconds ?? 0) > 0 }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("FF7 FLAC Converter").font(.title.bold())
                Text(status).foregroundStyle(.secondary)
                Button("Import PSF files and libraries") { showingImporter = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(converting)
                Button(converting ? "Converting..." : "Convert all ready tracks to FLAC") {
                    convertAll()
                }
                .buttonStyle(.borderedProminent)
                .disabled(converting || ready.isEmpty)
                if !outputs.isEmpty {
                    Button("Export all FLAC files") { showingExport = true }
                        .buttonStyle(.borderedProminent)
                    Text("\(outputs.count) FLAC file(s) ready to save to Files.")
                        .font(.footnote)
                }
                List {
                    ForEach(tracks) { track in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.metadata?.title ?? track.filename).font(.headline)
                            Text(track.filename).font(.caption).foregroundStyle(.secondary)
                            if let duration = track.metadata?.totalSeconds {
                                Text(String(format: "Declared duration: %.1f seconds including fade", duration))
                            }
                            if !track.missingLibraries.isEmpty {
                                Text("Missing libraries: " + track.missingLibraries.joined(separator: ", "))
                                    .foregroundStyle(.red)
                            }
                            if let problem = track.problem {
                                Text(problem).foregroundStyle(.red)
                            }
                        }
                    }
                    ForEach(outputs, id: \.self) { url in
                        ShareLink(item: url) {
                            Label(url.lastPathComponent, systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("Converter")
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): importFiles(urls)
                case .failure(let error): status = "Import failed: \(error.localizedDescription)"
                }
            }
            .sheet(isPresented: $showingExport) { ExportSheet(urls: outputs) }
        }
    }

    private func importFiles(_ urls: [URL]) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FF7Sources", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { status = "Cannot create working directory: \(error.localizedDescription)"; return }
        outputs = []
        var loaded: [(name: String, url: URL)] = []
        var failures: [ImportedPSF] = []
        var seen = Set<String>()
        for url in urls {
            let name = url.lastPathComponent
            let lower = name.lowercased()
            if seen.contains(lower) {
                failures.append(ImportedPSF(filename: name, source: nil, metadata: nil,
                                            problem: "Duplicate filename; cannot resolve libraries safely.",
                                            missingLibraries: []))
                continue
            }
            seen.insert(lower)
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let target = folder.appendingPathComponent(name)
                try FileManager.default.copyItem(at: url, to: target)
                loaded.append((name, target))
            } catch {
                failures.append(ImportedPSF(filename: name, source: nil, metadata: nil,
                                            problem: "Cannot read file: \(error.localizedDescription)",
                                            missingLibraries: []))
            }
        }
        var metadataByFilename: [String: PSFTrackMetadata] = [:]
        for file in loaded {
            if let metadata = try? PSFMetadataReader.read(Data(contentsOf: file.url)) {
                metadataByFilename[file.name.lowercased()] = metadata
            }
        }
        tracks = loaded.compactMap { file -> ImportedPSF? in
            let ext = (file.name as NSString).pathExtension.lowercased()
            guard ext == "psf" || ext == "minipsf" else { return nil }
            guard let metadata = metadataByFilename[file.name.lowercased()] else {
                return ImportedPSF(filename: file.name, source: nil, metadata: nil,
                                   problem: "Invalid or unsupported PSF header", missingLibraries: [])
            }
            let missing = PSFDependencies.missing(for: file.name,
                                                   metadataByFilename: metadataByFilename)
            return ImportedPSF(filename: file.name, source: file.url, metadata: metadata,
                               problem: nil, missingLibraries: missing)
        } + failures
        status = "Imported \(loaded.count) files; \(ready.count) track(s) ready."
    }

    private func convertAll() {
        let selected = ready
        guard !selected.isEmpty else { return }
        converting = true
        outputs = []
        status = "Converting 1 of \(selected.count)..."
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FF7Exports", isDirectory: true)
        DispatchQueue.global(qos: .userInitiated).async {
            try? FileManager.default.removeItem(at: folder)
            do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
            catch {
                DispatchQueue.main.async {
                    status = "Cannot create export folder: \(error.localizedDescription)"
                    converting = false
                }
                return
            }
            var completed: [URL] = []
            var errors: [String] = []
            for (index, track) in selected.enumerated() {
                DispatchQueue.main.async { status = "Converting \(index + 1) of \(selected.count): \(track.filename)" }
                guard let source = track.source else { continue }
                let stem = (track.filename as NSString).deletingPathExtension
                let output = folder.appendingPathComponent(stem).appendingPathExtension("flac")
                do {
                    try PSFConversion.convert(source: source, destination: output,
                                              declaredSeconds: track.metadata?.totalSeconds)
                    completed.append(output)
                } catch {
                    errors.append("\(track.filename): \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                outputs = completed
                converting = false
                status = "\(completed.count) converted, \(errors.count) failed." +
                         (errors.isEmpty ? "" : "\n" + errors.joined(separator: "\n"))
            }
        }
    }
}
