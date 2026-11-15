import Foundation

struct FocusFenceRulesCache {
    let directory: URL

    static var production: FocusFenceRulesCache {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return FocusFenceRulesCache(directory: support.appendingPathComponent("3F Browser/FocusFence", isDirectory: true))
    }

    var rulesURL: URL { directory.appendingPathComponent("rules-v1.json") }

    func save(_ data: Data) -> Bool {
        // Legacy cached snapshots are normalized only for in-memory offline
        // enforcement. Never write that compatibility projection back as a
        // fresh server snapshot; network writes require the current schema.
        guard Self.isUsable(data) else { return false }
        guard let normalized = Self.normalizedRules(data) else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try normalized.write(to: rulesURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func load() -> Data? {
        guard let data = try? Data(contentsOf: rulesURL) else { return nil }
        return Self.normalizedCachedRules(data)
    }

    private static func normalizedCachedRules(_ data: Data) -> Data? {
        normalizedRules(data)
    }

    // Snapshot of Focus Fence adult host rules v1.0.8. Older FF builds omit
    // adultProtected* fields, so only these known adult hosts/URL stems are
    // elevated above exceptions when migrating a complete legacy policy.
    private static let legacyAdultHostRules: Set<String> = Set("""
        10musume.com
        19wiki13.com
        19wiki17.com
        1pondo.tv
        4tube.com
        a-v19.com
        a3.xbbg.tv
        admireme.vip
        adultfriendfinder.com
        adultwork.com
        anysex.com
        ashleymadison.com
        asstr.org
        av19d.org
        av19e.org
        avgle.com
        babes.com
        badoinkvr.com
        bangbros.com
        beeg.com
        bgu11.com
        bgu12.com
        bongacams.com
        bongamodels.com
        boyfriendtv.com
        brazzers.com
        cam4.com
        cambro.tv
        camcontacts.com
        camfuze.com
        camgasm.com
        camgirls.com
        camhub.cc
        camhub.com
        camonster.com
        camplace.com
        camrabbit.com
        cams.com
        camshowdownload.com
        camsoda.com
        camster.com
        camversity.com
        camwhores.tv
        camwhoreshd.com
        camwithher.com
        caribbeancom.com
        chaturbate.com
        chaturbate.eu
        clips4sale.com
        daav7.com
        daav8.com
        daftsex.com
        digitalplayground.com
        dinotube.com
        dmm.co.jp
        drtuber.com
        e621.net
        empflix.com
        eporner.com
        eros.com
        escortbabylon.net
        extremetube.com
        fakku.net
        fancentro.com
        fansly.com
        fanvue.com
        fapdu.com
        fc2.com
        fetlife.com
        flirt4free.com
        fullporner.com
        fuq.com
        gaytube.com
        gelbooru.com
        gifdeliverynetwork.com
        gotporn.com
        hanime.tv
        hclips.com
        hellporno.com
        hentai-foundry.com
        hentai.tv
        hentai2read.com
        hentaifox.com
        hentaihaven.org
        hentaihaven.xxx
        hentaihere.com
        hentaipulse.com
        heyzo.com
        highcookie.com
        hitomi.la
        hqporner.com
        imagefap.com
        imlive.com
        iwantclips.com
        jable.tv
        jaddal45.top
        jav.guru
        javhd.com
        javlibrary.com
        javmost.com
        jerkmate.com
        jogemoa23.com
        jogemoa40.com
        juso3.net
        jusohot7.com
        jusomoa.org
        justfor.fans
        keezmovies.com
        kr23.ddaltube.com
        kr29.ddaltube.com
        kr34.javgirl.co
        kr35.javgirl.co
        largeporntube.com
        letmejerk.com
        lewd.ninja
        listcrawler.com
        literotica.com
        livejasmin.com
        liveprivates.com
        lobstertube.com
        loyalfans.com
        manyvids.com
        melonstube.com
        men.com
        mingky01.live
        mingky04.live
        mingky05.com
        mingky16.com
        mingky26.com
        missav.com
        modelhub.com
        mofos.com
        motherless.com
        mydirtyhobby.com
        myfreecams.com
        naughtyamerica.com
        netfapx.com
        netflav.com
        nhentai.com
        nhentai.net
        niteflirt.com
        noodlemagazine.com
        nuvid.com
        onlyfans.com
        onlyfans.tv
        phncdn.com
        porn.com
        porn00.org
        porn300.com
        porn4days.com
        porndig.com
        porngo.com
        pornhat.com
        pornhd.com
        pornhits.com
        pornhub.com
        pornhub.net
        pornhub.org
        pornhubpremium.com
        pornid.xxx
        pornkai.com
        pornmd.com
        pornone.com
        porntrex.com
        porntube.com
        pornzog.com
        privatedelights.ch
        proporn.com
        pururin.io
        r18.com
        realitykings.com
        recurbate.com
        redbogo28.com
        redgifs.com
        redko6.com
        redtube.com
        royalcams.com
        rule34.xxx
        sankakucomplex.com
        seeking.com
        seekingarrangement.com
        sex.com
        sexlikereal.com
        sexstories.com
        simply-hentai.com
        skipthegames.com
        slixa.com
        slutload.com
        spankbang.com
        streamate.com
        stripchat.com
        sugardaddy.com
        sunporno.com
        supjav.com
        sxyprn.com
        thisav.com
        tnaflix.com
        tokyo-hot.com
        tryst.link
        tsumino.com
        tube8.com
        tube8.fr
        tubegalore.com
        twistys.com
        txxx.com
        viptube.com
        visit-x.net
        vivastreet.com
        vrbangers.com
        vrporn.com
        wankzvr.com
        whatsyourprice.com
        xcams.com
        xhamster.com
        xhamster.desi
        xhamster2.com
        xhamsterlive.com
        xnxx.com
        xnxx.tv
        xnxx2.com
        xvideos.com
        xvideos.es
        xvideos.red
        xvideos2.com
        xxxbunker.com
        yaburi67.com
        yaburi70.com
        yadongkorea17.com
        yadongkorea7.com
        yadongparty15.com
        yadongparty6.com
        yadongtv107.com
        yadongtv96.com
        yako1234.com
        yasyadong04.tv
        ydtour80.sbs
        ydtour90.sbs
        ym-05.com
        yobt.com
        youjizz.com
        youporn.com
        """.split(whereSeparator: \.isWhitespace).map(String.init))
    private static let legacyAdultURLParts: Set<String> = ["mingky", "yadong"]

    static func normalizedRules(_ data: Data) -> Data? {
        if isUsable(data) { return data }
        guard var rules = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let adultKeys = ["adultProtectedDomains", "adultProtectedUrlParts", "adultProtectedKeywords"]
        // FF versions can still return the complete legacy policy without these
        // newer optional protection arrays. Normalize that payload before both
        // caching and enforcement, while rejecting partial/null/malformed fields.
        guard adultKeys.allSatisfy({ rules[$0] == nil }),
              rules["blockedDomains"] is [String],
              rules["blockedUrlParts"] is [String],
              rules["keywords"] is [String],
              rules["blockExceptions"] is [String] else { return nil }
        func normalizedDomain(_ value: String) -> String {
            var domain = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if domain.hasPrefix("*.") { domain = String(domain.dropFirst(2)) }
            domain = domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return domain.hasPrefix("www.") ? String(domain.dropFirst(4)) : domain
        }
        let blockedDomains = rules["blockedDomains"] as! [String]
        let blockedURLParts = rules["blockedUrlParts"] as! [String]
        rules["adultProtectedDomains"] = blockedDomains.filter {
            Self.legacyAdultHostRules.contains(normalizedDomain($0))
        }
        rules["adultProtectedUrlParts"] = blockedURLParts.filter {
            Self.legacyAdultURLParts.contains($0.lowercased())
        }
        rules["adultProtectedKeywords"] = [String]()
        guard let normalized = try? JSONSerialization.data(withJSONObject: rules), isUsable(normalized) else { return nil }
        return normalized
    }

    private static func isUsable(_ data: Data) -> Bool {
        guard let rules = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              rules["blockedDomains"] is [String],
              rules["blockedUrlParts"] is [String],
              rules["adultProtectedDomains"] is [String],
              rules["adultProtectedUrlParts"] is [String],
              rules["adultProtectedKeywords"] is [String],
              rules["keywords"] is [String],
              rules["blockExceptions"] is [String] else { return false }
        return true
    }
}
