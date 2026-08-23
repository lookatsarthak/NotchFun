//
//  URLCleaner.swift
//  boringNotch
//

import Foundation

/// Strips tracking parameters out of a copied link.
///
/// Deny-list only, never an allow-list. A parameter is removed because it is known by
/// name to be a tracker, not because it failed to look useful — the failure mode of
/// guessing wrong in that direction is a link that no longer opens the thing the user
/// meant to share, which is far worse than leaving a tracking token in it.
///
/// Two more rules keep that promise:
///
/// - Only a copy that is *exactly one* URL is touched. A sentence containing a link is
///   left alone, because rewriting text around a link is a different and riskier job.
/// - Nothing is rewritten unless something was actually removed. `URLComponents` will
///   happily re-encode a query on the way out, so returning `nil` for the no-op case is
///   what guarantees an untouched link is byte-identical to what was copied.
///
/// The history entry is never modified — this runs at the moment an entry is written back
/// to the pasteboard, so turning the setting off restores the original immediately.
enum URLCleaner {

    struct Result: Equatable {
        let cleaned: String
        /// The parameter names removed, in the order they appeared.
        let removed: [String]
    }

    /// - Returns: the cleaned link, or `nil` if `text` is not a single http(s) URL or
    ///   there was nothing to remove.
    static func clean(_ text: String) -> Result? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }

        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              let items = components.queryItems,
              !items.isEmpty
        else { return nil }

        let scoped = scopedParameters(for: host)
        var removed: [String] = []
        let kept = items.filter { item in
            guard isTracking(item.name.lowercased(), scopedTo: scoped) else { return true }
            removed.append(item.name)
            return false
        }

        guard !removed.isEmpty else { return nil }
        // nil, not []: an empty array leaves a bare "?" on the end of the URL.
        components.queryItems = kept.isEmpty ? nil : kept
        guard let cleaned = components.string else { return nil }
        return Result(cleaned: cleaned, removed: removed)
    }

    /// Whether `clean` would change this text. Used to mark entries in the list, so the
    /// rewrite is never a surprise.
    static func wouldClean(_ text: String) -> Bool { clean(text) != nil }

    // MARK: - What counts as tracking

    private static func isTracking(_ name: String, scopedTo scoped: Set<String>) -> Bool {
        if globalPrefixes.contains(where: name.hasPrefix) { return true }
        if globalParameters.contains(name) { return true }
        return scoped.contains(name)
    }

    private static func scopedParameters(for host: String) -> Set<String> {
        var result: Set<String> = []
        for (domain, names) in hostScopedParameters
        where host == domain || host.hasSuffix("." + domain) {
            result.formUnion(names)
        }
        return result
    }

    /// `utm_source`, `utm_campaign`, and the long tail of vendor-specific `utm_*` keys.
    static let globalPrefixes: Set<String> = ["utm_"]

    /// Names that mean the same thing everywhere and identify the person following the
    /// link rather than selecting any content.
    static let globalParameters: Set<String> = [
        // Google
        "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "gad_source", "gad_campaignid",
        "srsltid", "ncid", "_ga", "_gl",
        // Meta
        "fbclid", "fb_action_ids", "fb_action_types", "fb_ref", "fb_source", "fbs_aeid",
        "igshid", "igsh",
        // Microsoft, TikTok, X
        "msclkid", "ttclid", "twclid",
        // Email and marketing platforms
        "mc_cid", "mc_eid", "mkt_tok", "_hsenc", "_hsmi", "__hsfp", "__hssc", "__hstc",
        "hsctatracking", "vero_conv", "vero_id", "ml_subscriber", "ml_subscriber_hash",
        "oly_anon_id", "oly_enc_id", "wickedid", "epik", "rb_clickid", "irclickid",
        // Yandex, Yahoo
        "yclid", "ysclid", "_openstat",
        "guccounter", "guce_referrer", "guce_referrer_sig",
        // Branch, AWS
        "_branch_match_id", "_branch_referrer",
        "sc_campaign", "sc_channel", "sc_content", "sc_country", "sc_geo", "sc_medium",
        "sc_outcome", "sc_publisher",
    ]

    /// Names that are trackers on these hosts and ordinary query keys elsewhere.
    ///
    /// `si` is a share token on Spotify and YouTube and a perfectly reasonable parameter
    /// on someone's blog; `s` and `t` on x.com likewise. Scoping them is the difference
    /// between a useful feature and one that quietly breaks links.
    static let hostScopedParameters: [String: Set<String>] = {
        var map: [String: Set<String>] = [
            // Deliberately absent from the YouTube set: t, v, list, index, start.
            // Those carry the timestamp, the video and the playlist position.
            "youtube.com": ["si", "pp", "feature", "kw"],
            "youtu.be": ["si", "pp", "feature"],
            "spotify.com": ["si", "nd", "_branch"],
            "x.com": ["s", "t", "ref_src", "ref_url"],
            "twitter.com": ["s", "t", "ref_src", "ref_url"],
            "linkedin.com": ["trk", "trkinfo", "originalsubdomain", "li_fat_id", "refid"],
            "reddit.com": ["share_id", "correlation_id", "ref_source", "ref_campaign", "rdt"],
            "tiktok.com": ["is_from_webapp", "sender_device", "refer", "_r", "_t"],
            "ebay.com": ["_trkparms", "_trksid", "mkcid", "mkrid", "campid", "toolid", "mkevt"],
            "aliexpress.com": ["spm", "scm", "scm_id", "pvid", "algo_pvid"],
            "taobao.com": ["spm", "scm"],
            "medium.com": ["source"],
        ]
        // Amazon runs the same parameters on every storefront, and `hasSuffix` matching
        // cannot generalise amazon.com to amazon.co.uk.
        let amazon: Set<String> = [
            "ref", "ref_", "psc", "th", "tag", "linkcode", "creative", "creativeasin",
            "camp", "ascsubtag", "smid", "content-id", "dib", "dib_tag", "qid", "sr",
            "pd_rd_w", "pd_rd_wg", "pd_rd_r", "pd_rd_i",
            "pf_rd_p", "pf_rd_r", "pf_rd_s", "pf_rd_t", "pf_rd_i", "pf_rd_m",
        ]
        for host in [
            "amazon.com", "amazon.co.uk", "amazon.de", "amazon.fr", "amazon.it",
            "amazon.es", "amazon.nl", "amazon.se", "amazon.pl", "amazon.ca",
            "amazon.com.mx", "amazon.com.br", "amazon.com.au", "amazon.co.jp",
            "amazon.in", "amazon.ae", "amazon.sa", "amazon.sg", "amazon.com.tr",
        ] { map[host] = amazon }
        return map
    }()
}
