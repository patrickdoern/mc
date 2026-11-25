import Testing
@testable import MCCore

@Suite struct LinkTargetTests {
    @Test func recognizesLinkAddresses() {
        #expect(LinkTarget.isLink("mc://Mac"))
        #expect(LinkTarget.isLink("  MC://Mac"))
        #expect(!LinkTarget.isLink("smb://host/share"))
        #expect(!LinkTarget.isLink("Mac"))
    }

    @Test func parsesName() {
        #expect(LinkTarget.parse("mc://Büro-Mac") == LinkTarget(name: "Büro-Mac"))
        #expect(LinkTarget.parse(" MC://Büro-Mac/ ") == LinkTarget(name: "Büro-Mac"))
    }

    @Test func decodesPercentEncoding() {
        #expect(LinkTarget.parse("mc://Patricks%20MacBook%20Pro") == LinkTarget(name: "Patricks MacBook Pro"))
    }

    @Test func keepsNameWithoutValidEncoding() {
        #expect(LinkTarget.parse("mc://100% Mac") == LinkTarget(name: "100% Mac"))
    }

    @Test func rejectsMissingName() {
        #expect(LinkTarget.parse("mc://") == nil)
        #expect(LinkTarget.parse("mc:///") == nil)
        #expect(LinkTarget.parse("ftp://Mac") == nil)
    }

    @Test func displayNameParsesBack() {
        let target = LinkTarget(name: "Patricks MacBook Pro")
        #expect(target.displayName == "mc://Patricks MacBook Pro")
        #expect(LinkTarget.parse(target.displayName) == target)
    }
}
