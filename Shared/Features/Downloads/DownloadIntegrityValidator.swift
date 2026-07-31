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

        let expectedContentLength = response.expectedContentLength
        guard expectedContentLength <= 0 || expectedContentLength == stagedFileSize else {
            throw DownloadIntegrityFailure.contentLengthMismatch
        }
    }
}

enum DownloadIntegrityFailure: Error, Equatable {
    case invalidResponse
    case unsuccessfulStatus
    case unexpectedContentType
    case emptyFile
    case contentLengthMismatch
}
