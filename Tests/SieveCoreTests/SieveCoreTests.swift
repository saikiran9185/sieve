import Testing
import Foundation
@testable import SieveCore

// These cover the decisions the engine makes offline — no network, no database, no
// clock. They exist mainly so the Windows and Linux builds prove the engine *behaves*
// the same as on macOS, not merely that it compiles there.

// MARK: - Deduplication

@Suite("Deduplication")
struct DedupeTests {

    @Test("A DOI identifies a paper regardless of title or year")
    func doiWins() {
        let a = Dedupe.key(doi: "10.1000/XYZ", title: "One title", year: 2020)
        let b = Dedupe.key(doi: "  10.1000/xyz  ", title: "A different title", year: 1999)
        #expect(a == b)
        #expect(a == "doi:10.1000/xyz")
    }

    @Test("Without a DOI, a long title matches across a year disagreement")
    func longTitleIgnoresYear() {
        // Online-first publication routinely dates the same article a year apart.
        let title = "Cosmetic packaging and consumer perception of sustainability in urban India"
        #expect(Dedupe.key(doi: "", title: title, year: 2021)
             == Dedupe.key(doi: "", title: title, year: 2022))
    }

    @Test("A short title is too weak to match on alone, so the year joins the key")
    func shortTitleKeepsYear() {
        #expect(Dedupe.key(doi: "", title: "Packaging", year: 2021)
             != Dedupe.key(doi: "", title: "Packaging", year: 2022))
    }

    @Test("Punctuation and case do not split one paper into two")
    func titleNormalisation() {
        #expect(Dedupe.key(doi: "", title: "Design, Research & Practice: A Review", year: 2020)
             == Dedupe.key(doi: "", title: "design research practice a review", year: 2020))
    }

    @Test("A missing year is not treated as a year")
    func missingYear() {
        #expect(Dedupe.key(doi: "", title: "Short", year: nil) == "t:short:")
    }
}

// MARK: - OpenAlex abstracts

@Suite("OpenAlex inverted abstracts")
struct InvertedAbstractTests {

    @Test("Words come back in position order")
    func reconstructsOrder() {
        let inverted: [String: [Int]] = ["Sustainable": [0], "packaging": [1], "matters": [2]]
        #expect(OpenAlex.invertedAbstract(inverted) == "Sustainable packaging matters")
    }

    @Test("A word repeated at several positions appears at each of them")
    func repeatedWords() {
        let inverted: [String: [Int]] = ["the": [0, 2], "cat": [1], "hat": [3]]
        #expect(OpenAlex.invertedAbstract(inverted) == "the cat the hat")
    }

    @Test("Anything that is not an inverted index yields no abstract")
    func rejectsJunk() {
        #expect(OpenAlex.invertedAbstract(nil) == "")
        #expect(OpenAlex.invertedAbstract("a plain string") == "")
        #expect(OpenAlex.invertedAbstract([1, 2, 3]) == "")
    }
}

// MARK: - Link safety

@Suite("Link allow-list")
struct SafeLinkTests {

    @Test("Ordinary web traffic is allowed", arguments: [
        "https://doi.org/10.1000/xyz",
        "http://example.org/paper.pdf"
    ])
    func allowsWeb(_ url: String) {
        #expect(SafeLink.web(url) != nil)
    }

    // Every link Sieve opens arrives from an external source — a search API's JSON, a
    // .bib someone else exported — so anything that is not plain web traffic is refused.
    @Test("Everything else is refused", arguments: [
        "file:///etc/passwd",
        "ssh://box/repo",
        "javascript:alert(1)",
        "ftp://example.org/x",
        "https://",
        "",
        "   "
    ])
    func refusesOther(_ url: String) {
        #expect(SafeLink.web(url) == nil)
    }

    @Test("Scheme comparison is case-insensitive")
    func schemeCasing() {
        #expect(SafeLink.web("HTTPS://example.org/a") != nil)
    }

    @Test("Surrounding whitespace does not defeat the check")
    func trimsInput() {
        #expect(SafeLink.web("  https://example.org/a  ") != nil)
    }

    @Test("A DOI is preferred over whatever link the record carried")
    func doiPreferred() {
        let u = SafeLink.forPaper(url: "https://example.org/landing", doi: "10.1000/xyz")
        #expect(u?.absoluteString == "https://doi.org/10.1000/xyz")
    }

    @Test("Without a DOI the record's own link is used")
    func fallsBackToURL() {
        let u = SafeLink.forPaper(url: "https://example.org/landing", doi: "")
        #expect(u?.absoluteString == "https://example.org/landing")
    }

    @Test("A record with neither a DOI nor a safe link yields nothing")
    func neither() {
        #expect(SafeLink.forPaper(url: "file:///tmp/x", doi: "") == nil)
    }
}

// MARK: - External sites

@Suite("External sites")
struct ExternalSiteTests {

    @Test("The query is substituted and percent-encoded")
    func buildsURL() throws {
        let site = try #require(ExternalSite.all.first)
        let url = try #require(site.url(for: "design research"))
        #expect(!url.absoluteString.contains("{q}"))
        #expect(!url.absoluteString.contains(" "))
    }

    @Test("Every site is a real web link with a usable template")
    func allSitesWellFormed() {
        for site in ExternalSite.all {
            #expect(site.template.contains("{q}"), "\(site.name) has no query placeholder")
            #expect(!site.howTo.isEmpty, "\(site.name) has no instructions")
            #expect(SafeLink.web(site.url(for: "x")?.absoluteString ?? "") != nil,
                    "\(site.name) does not build a safe web URL")
        }
    }

    @Test("Site ids are unique")
    func uniqueIDs() {
        let ids = ExternalSite.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}

// MARK: - Credentials

@Suite("Secret storage")
struct SecretStoreTests {

    @Test("A key round-trips")
    func roundTrip() {
        let store = EphemeralSecretStore()
        store.set("abc123", for: "sieve.test")
        #expect(store.get("sieve.test") == "abc123")
    }

    @Test("Surrounding whitespace is stripped, since keys are pasted in by hand")
    func trims() {
        let store = EphemeralSecretStore()
        store.set("  abc123\n", for: "sieve.test")
        #expect(store.get("sieve.test") == "abc123")
    }

    @Test("Storing an empty value clears the key rather than storing blank")
    func emptyClears() {
        let store = EphemeralSecretStore()
        store.set("abc123", for: "sieve.test")
        store.set("   ", for: "sieve.test")
        #expect(store.get("sieve.test") == "")
    }

    @Test("An unset key reads as empty, never nil-crashes")
    func missingKey() {
        #expect(EphemeralSecretStore().get("nope") == "")
    }
}

// MARK: - Provider registry

@Suite("Provider registry")
struct ProviderRegistryTests {

    @Test("All fourteen databases are registered")
    func count() {
        #expect(ProviderRegistry.all.count == 14)
    }

    @Test("Provider names are unique and non-empty")
    func names() {
        let names = ProviderRegistry.all.map(\.name)
        let anyEmpty = names.contains(where: { $0.isEmpty })
        #expect(Set(names).count == names.count)
        #expect(!anyEmpty)
    }

    @Test("A fresh install can search without pasting any key")
    func keylessDefaults() {
        let defaults = ProviderRegistry.defaultEnabledNames
        #expect(!defaults.isEmpty)
        for name in defaults {
            let provider = ProviderRegistry.named(name)
            #expect(provider?.needsKey == false)
        }
    }

    @Test("A key-gated provider stays unready until a key exists")
    func gatedProvidersNotReady() {
        Secrets.store = EphemeralSecretStore()
        for provider in ProviderRegistry.all where provider.needsKey {
            #expect(provider.isReady == false, "\(provider.name) claims ready with no key")
        }
    }

    @Test("Pasting a key makes its provider ready")
    func keyMakesReady() throws {
        let store = EphemeralSecretStore()
        Secrets.store = store
        let candidate = ProviderRegistry.all.first(where: { $0.needsKey })
        let gated = try #require(candidate)
        let account = try #require(gated.keyDefault)
        store.set("a-key", for: account)
        #expect(gated.isReady)
    }

    @Test("Every key-gated provider tells you where to get a key")
    func gatedProvidersExplainThemselves() {
        for provider in ProviderRegistry.all where provider.needsKey {
            #expect(provider.signupURL != nil, "\(provider.name) has no signup URL")
            #expect(SafeLink.web(provider.signupURL ?? "") != nil,
                    "\(provider.name) signup URL is not a safe web link")
        }
    }

    @Test("Every provider describes itself")
    func blurbs() {
        for provider in ProviderRegistry.all {
            #expect(!provider.blurb.isEmpty, "\(provider.name) has no blurb")
        }
    }
}
