import Testing

@Test func deployEventsHaveMessages() {
    #expect(DeployMessage(event: "start") == .start)
    #expect(DeployMessage(event: "success") == .success)
    #expect(DeployMessage(event: "failure") == .failure)
    #expect(DeployMessage(event: "something else") == nil)
}

@Test func deployMessagesAreDistinct() {
    let keys = DeployMessage.allCases.map(\.key)
    #expect(Set(keys).count == keys.count)
}
