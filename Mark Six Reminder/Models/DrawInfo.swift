import Foundation

/// A stable representation of a Mark Six draw returned by the Worker.
struct DrawInfo: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let drawNumber: String
    let drawDate: String
    let salesCloseAt: String
    let estimatedFirstPrizeFund: Int?
    let jackpot: Int?
    let status: String
    let mainNumbers: [Int]
    let specialNumber: Int?
    let updatedAt: String
    let sourceURL: String
}
