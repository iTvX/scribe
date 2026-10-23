import RimeKit
import ScribeCore
import Testing

private func candidates(_ count: Int) -> [Candidate] {
    (0..<count).map { Candidate(text: "候选\($0)") }
}

@Test func selectKeysWinOverSelectLabels() {
    let menu = CandidateMenu(candidates: candidates(3), pageSize: 3, selectLabels: ["一", "二", "三"], selectKeys: "asd")
    let snapshot = CandidateSnapshot(menu: menu, composition: nil)
    #expect(snapshot.entries.map(\.label) == ["a", "s", "d"])
}

@Test func selectLabelsWhenThereAreNoSelectKeys() {
    let menu = CandidateMenu(candidates: candidates(3), pageSize: 3, selectLabels: ["一", "", "三"])
    let snapshot = CandidateSnapshot(menu: menu, composition: nil)
    #expect(snapshot.entries.map(\.label) == ["一", "", "三"])
}

@Test func numbersWithoutKeysOrLabels() {
    let menu = CandidateMenu(candidates: candidates(10), pageSize: 10)
    let snapshot = CandidateSnapshot(menu: menu, composition: nil)
    #expect(snapshot.entries.map(\.label) == ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"])
}

@Test func numbersPastTheEndOfTheKeys() {
    let menu = CandidateMenu(candidates: candidates(4), pageSize: 4, selectKeys: "ab")
    let snapshot = CandidateSnapshot(menu: menu, composition: nil)
    #expect(snapshot.entries.map(\.label) == ["a", "b", "3", "4"])
}

@Test func preeditCarriesSelectionAndCaret() {
    let composition = Composition(preedit: "ni hao", cursor: 6, selectionStart: 0, selectionEnd: 2)
    let snapshot = CandidateSnapshot(menu: nil, composition: composition)
    #expect(snapshot.preedit == Preedit(text: "ni hao", selectedRange: 0..<2, caret: 6))
    #expect(snapshot.entries.isEmpty)
}
