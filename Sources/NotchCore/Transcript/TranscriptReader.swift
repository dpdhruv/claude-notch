import Foundation

enum TranscriptReader {
    struct Tail {
        let entries: [TranscriptEntry]
        /// True when the read reached the start of the file, so reading more bytes cannot help.
        let coversWholeFile: Bool
    }

    /// Reads the last `bytes` of a transcript. Transcripts can reach hundreds of megabytes, so only the end is parsed.
    static func readTail(of url: URL, bytes: Int) -> Tail {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Tail(entries: [], coversWholeFile: true) }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return Tail(entries: [], coversWholeFile: true) }

        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if start > 0, !lines.isEmpty { lines.removeFirst() }   // the first line is cut off mid-way
        let entries = lines.compactMap { line -> TranscriptEntry? in
            guard let json = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { return nil }
            return TranscriptEntry(json)
        }
        return Tail(entries: entries, coversWholeFile: start == 0)
    }
}
