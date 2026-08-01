import Foundation

enum DownloadIntegrityValidator {
    static func validate(response: URLResponse?, stagedFileSize: Int64) throws {
        guard let response = response as? HTTPURLResponse else {
            throw DownloadIntegrityFailure.invalidResponse
        }

        guard (200 ..< 300).contains(response.statusCode) else {
            throw DownloadIntegrityFailure.unsuccessfulStatus
        }

        if let mimeType = response.mimeType?.lowercased(),
           mimeType.hasPrefix("text/")
           || mimeType == "application/json"
           || mimeType.contains("xml")
        {
            throw DownloadIntegrityFailure.unexpectedContentType
        }

        guard stagedFileSize > 0 else {
            throw DownloadIntegrityFailure.emptyFile
        }

        let expectedFileSize = expectedCompleteFileSize(from: response)
        guard expectedFileSize == nil || expectedFileSize == stagedFileSize else {
            throw DownloadIntegrityFailure.contentLengthMismatch
        }
    }

    private static func expectedCompleteFileSize(from response: HTTPURLResponse) -> Int64? {
        if response.statusCode == 206 {
            guard let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
                  let totalComponent = contentRange.split(separator: "/").last,
                  totalComponent != "*"
            else {
                return nil
            }
            return Int64(totalComponent)
        }

        let expectedContentLength = response.expectedContentLength
        return expectedContentLength > 0 ? expectedContentLength : nil
    }
}

enum DownloadIntegrityFailure: Error, Equatable {
    case invalidResponse
    case unsuccessfulStatus
    case unexpectedContentType
    case emptyFile
    case contentLengthMismatch
}
