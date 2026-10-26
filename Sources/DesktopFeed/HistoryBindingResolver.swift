import Foundation

struct BindingRoot: Equatable {
    let id: String
    let path: String
    let title: String?
    let recency: Double
}

struct BindingCandidates {
    let roots: [BindingRoot]
    let history: [SessionRow]
    let exceedsLimit: Bool
}

struct BindingResolution {
    var rows: [SessionRow]
    var files: [String: RolloutBindingFile]
    var uncertain: Bool
}

/// Discovers an association only by matching two complete records in an
/// eligible root's own file. SQL identifiers, titles and dates are not aliases.
struct HistoryBindingResolver {
    private struct Key: Equatable {
        let turn: String
        let offset: UInt64
    }
    private struct Proof {
        let rootID: String
        let path: String
        let key: Key
        let identity: RolloutBindingFile.Identity
    }
    private struct Search {
        let key: Key
        var visited = Set<String>()
        var matches: [String: Proof] = [:]
        var unreadable = false
        var retryAfter: ContinuousClock.Instant?
    }
    private var proofs: [String: Proof] = [:]
    private var searches: [String: Search] = [:]
    private var catalog: [String: String] = [:]

    mutating func reset() {
        proofs.removeAll()
        searches.removeAll()
        catalog.removeAll()
    }

    mutating func resolve(_ input: BindingCandidates, canonical: [SessionRow], home: URL,
                          now: ContinuousClock.Instant = .now) -> BindingResolution {
        let groups = Dictionary(grouping: input.roots, by: \.id)
        guard groups.values.allSatisfy({ $0.count == 1 }) else {
            return BindingResolution(rows: canonical, files: [:], uncertain: true)
        }
        let roots = groups.mapValues { $0[0] }
        let newCatalog = roots.mapValues(\.path)
        if catalog != newCatalog {
            searches.removeAll()
            proofs.removeAll()
            catalog = newCatalog
        }
        let namespaces = Set(input.history.map(\.id))
        proofs = proofs.filter { namespaces.contains($0.key) }
        searches = searches.filter { namespaces.contains($0.key) }
        let duplicateNamespaces = Set(Dictionary(grouping: input.history, by: \.id).filter { $0.value.count != 1 }.keys)
        let orderedRoots = input.roots.sorted {
            if $0.recency != $1.recency { return $0.recency > $1.recency }
            return $0.id < $1.id
        }
        var discoveryBytes = RolloutJSONLProjection.readBudget
        var discoveryOpens = 32
        var proposed: [(history: SessionRow, root: BindingRoot, file: RolloutBindingFile)] = []
        var uncertain = input.exceedsLimit
        for history in input.history {
            guard !duplicateNamespaces.contains(history.id) else {
                uncertain = true
                continue
            }
            let key = Key(turn: history.turnID, offset: history.offset)
            var lostKnownProof = false
            if let proof = proofs[history.id], let root = roots[proof.rootID], root.path == proof.path {
                do {
                    let file = try RolloutBindingFile(path: root.path, home: home)
                    if proof.key == key && proof.identity == file.identity {
                        try file.requireUnchanged()
                        proposed.append((history, root, file))
                        continue
                    }
                    if proof.key == key,
                       try file.verifies(stateID: root.id, turnID: history.turnID, offset: history.offset) {
                        proofs[history.id] = Proof(rootID: root.id, path: root.path, key: key, identity: file.identity)
                        proposed.append((history, root, file))
                        continue
                    }
                } catch { /* A changed proof is unknown; never turn it into running. */ }
                proofs.removeValue(forKey: history.id)
                searches.removeValue(forKey: history.id)
                uncertain = true
                lostKnownProof = true
            }
            var search = searches[history.id].flatMap { $0.key == key ? $0 : nil } ?? Search(key: key)
            search.unreadable = search.unreadable || lostKnownProof
            if let retryAfter = search.retryAfter {
                if now < retryAfter {
                    uncertain = uncertain || search.unreadable
                    continue
                }
                search = Search(key: key)
            }
            var found = false
            var openedMatches: [String: RolloutBindingFile] = [:]
            for root in orderedRoots where !search.visited.contains(root.id) {
                guard discoveryOpens > 0, discoveryBytes >= 131_073 else { break }
                discoveryOpens -= 1
                search.visited.insert(root.id)
                do {
                    let file = try RolloutBindingFile(path: root.path, home: home)
                    // This is only a rejection filter; file length never proves activity.
                    guard history.offset < file.size else { continue }
                    defer { discoveryBytes -= min(discoveryBytes, file.bytesRead) }
                    guard try file.verifies(stateID: root.id, turnID: history.turnID, offset: history.offset) else {
                        if !file.headerStateConfirmed { search.unreadable = true }
                        continue
                    }
                    search.matches[root.id] = Proof(rootID: root.id, path: root.path, key: key, identity: file.identity)
                    openedMatches[root.id] = file
                    if search.matches.count > 1 { break }
                } catch {
                    // We cannot exclude this eligible root from a corrupt or
                    // unreadable record. Retry without inventing an association.
                    search.unreadable = true
                }
            }
            if search.matches.count > 1 {
                // Forked or copied files can contain the same turn. Recency
                // must never choose which root owns an ambiguous witness.
                search.unreadable = true
                search.retryAfter = now.advanced(by: .seconds(30))
                uncertain = true
            } else if search.visited.count == roots.count,
                      let match = search.matches.values.first, let root = roots[match.rootID] {
                do {
                    let file = try openedMatches[root.id] ?? RolloutBindingFile(path: root.path, home: home)
                    if file.identity != match.identity {
                        guard try file.verifies(stateID: root.id, turnID: history.turnID, offset: history.offset) else {
                            throw FeedError.invalidRollout
                        }
                    }
                    try file.requireUnchanged()
                    proofs[history.id] = Proof(rootID: root.id, path: root.path, key: key, identity: file.identity)
                    proposed.append((history, root, file))
                    found = true
                } catch { search.unreadable = true }
            }
            if !found {
                if search.visited.count < roots.count { uncertain = true }
                else {
                    search.retryAfter = now.advanced(by: .seconds(30))
                    uncertain = uncertain || search.unreadable
                }
            }
            searches[history.id] = search
        }
        // Two history namespaces must never claim the same root. A canonical
        // active turn also wins over no ambiguous fallback: neither is guessed.
        let collisions = Set(Dictionary(grouping: proposed, by: { $0.root.id }).filter { $0.value.count != 1 }.keys)
        var output = BindingResolution(rows: canonical, files: [:], uncertain: uncertain)
        for proposal in proposed {
            let root = proposal.root
            guard !collisions.contains(root.id) else {
                output.uncertain = true
                proofs.removeValue(forKey: proposal.history.id)
                continue
            }
            if let direct = canonical.first(where: { $0.id == root.id && $0.status == "inProgress" }) {
                if direct.turnID != proposal.history.turnID || direct.offset != proposal.history.offset {
                    output.rows.removeAll { $0.id == root.id }
                    output.uncertain = true
                }
                continue
            }
            let history = proposal.history
            output.rows.removeAll { $0.id == root.id }
            output.rows.append(SessionRow(id: root.id, path: root.path, turnID: history.turnID,
                status: history.status, offset: history.offset, completedAt: history.completedAt,
                title: root.title, itemType: history.itemType, itemStatus: history.itemStatus,
                activityAt: history.activityAt))
            output.files[root.id] = proposal.file
        }
        return output
    }
}
