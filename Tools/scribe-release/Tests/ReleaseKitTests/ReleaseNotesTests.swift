import ReleaseKit
import Testing

private let changelog = """
    # 更新记录

    ## 0.3.0

    - Third

    ## 0.2.0

    - Second, line one
    - Second, line two

    ### Details

    More about the second.

    ## 0.1.1

    ## 0.1.0

    - First
    """

@Test func sectionInTheMiddle() {
    #expect(ReleaseNotes.section(for: "0.2.0", in: changelog) == """
        - Second, line one
        - Second, line two

        ### Details

        More about the second.
        """)
}

@Test func lastSection() {
    #expect(ReleaseNotes.section(for: "0.1.0", in: changelog) == "- First")
}

@Test func missingSection() {
    #expect(ReleaseNotes.section(for: "0.4.0", in: changelog) == nil)
    // Only a whole heading matches.
    #expect(ReleaseNotes.section(for: "0.3", in: changelog) == nil)
}

@Test func emptySection() {
    #expect(ReleaseNotes.section(for: "0.1.1", in: changelog) == nil)
}

@Test func windowsLineEndings() {
    #expect(ReleaseNotes.section(for: "1.0.0", in: "## 1.0.0\r\n\r\n- One\r\n## 0.9.0\r\n- Old\r\n") == "- One")
}
