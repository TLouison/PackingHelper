//
//  AppLinks.swift
//  PackingHelper
//

import Foundation

/// Web pages the app links to. The privacy policy and support pages live on
/// packinghelper.app (PackingHelperSite repo); Terms of Use is Apple's standard EULA.
enum AppLinks {
    static let privacyPolicy = URL(string: "https://packinghelper.app/privacy/")!
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let support = URL(string: "https://packinghelper.app/support/")!
}
