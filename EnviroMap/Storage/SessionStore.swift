/// Export RoomPlan structure USDZ.
    private func exportRoomPlan(_ room: CapturedRoom, to url: URL) throws {
        try room.export(to: url)
    }