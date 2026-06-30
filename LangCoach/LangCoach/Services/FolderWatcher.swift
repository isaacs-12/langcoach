import Foundation
import CoreServices

/// Watches a directory tree with FSEvents and fires a debounced callback whenever
/// its contents change. Used to keep a mounted notes folder in sync while the app
/// is open. The callback is delivered on the main queue.
final class FolderWatcher {
    private let url: URL
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "com.langcoach.folderwatcher")
    private var stream: FSEventStreamRef?
    private var debounceItem: DispatchWorkItem?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    deinit { stop() }

    func start() {
        guard stream == nil else { return }
        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.scheduleNotify()
        }
        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &ctx,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5, // latency, seconds — FSEvents coalesces bursts for us
            flags
        ) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Extra debounce on top of FSEvents latency so a flurry of writes (e.g. an
    /// editor saving) results in a single sync.
    private func scheduleNotify() {
        debounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.onChange() }
        debounceItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }
}
