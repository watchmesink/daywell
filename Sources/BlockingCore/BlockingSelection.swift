import Foundation

/// Opaque Screen Time tokens, kept separate so different token kinds never collide.
public struct BlockingSelection: Codable, Equatable, Sendable {
    public var applications: [Data]
    public var categories: [Data]
    public var webDomains: [Data]

    public init(applications: [Data] = [], categories: [Data] = [], webDomains: [Data] = []) {
        self.applications = Self.sortedUnique(applications)
        self.categories = Self.sortedUnique(categories)
        self.webDomains = Self.sortedUnique(webDomains)
    }

    public var isEmpty: Bool { applications.isEmpty && categories.isEmpty && webDomains.isEmpty }

    public var normalized: Self {
        Self(applications: applications, categories: categories, webDomains: webDomains)
    }

    public func isSuperset(of other: Self) -> Bool {
        Set(applications).isSuperset(of: other.applications)
            && Set(categories).isSuperset(of: other.categories)
            && Set(webDomains).isSuperset(of: other.webDomains)
    }

    public func union(_ other: Self) -> Self {
        Self(applications: applications + other.applications,
             categories: categories + other.categories,
             webDomains: webDomains + other.webDomains)
    }

    public func validate() throws {
        for tokens in [applications, categories, webDomains] {
            guard tokens.allSatisfy({ !$0.isEmpty }), Set(tokens).count == tokens.count else {
                throw RuleError.invalidSelection
            }
            guard tokens.count <= 50 else { throw RuleError.tooManySelections }
        }
    }

    private static func sortedUnique(_ tokens: [Data]) -> [Data] {
        Array(Set(tokens)).sorted { $0.lexicographicallyPrecedes($1) }
    }

    // The flat keys retain compatibility with version 1 (one app) and version 2 (apps).
    private enum CodingKeys: String, CodingKey { case applications, application, categories, webDomains }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let applications: [Data]
        if values.contains(.applications) {
            applications = try values.decode([Data].self, forKey: .applications)
        } else {
            applications = try values.decodeIfPresent(Data.self, forKey: .application).map { [$0] } ?? []
        }
        self.init(applications: applications,
                  categories: try values.decodeIfPresent([Data].self, forKey: .categories) ?? [],
                  webDomains: try values.decodeIfPresent([Data].self, forKey: .webDomains) ?? [])
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(applications, forKey: .applications)
        try values.encode(categories, forKey: .categories)
        try values.encode(webDomains, forKey: .webDomains)
    }
}
