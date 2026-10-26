import Foundation
import Testing
@testable import SimpleVector
@testable import SimpleVectorCore
@testable import SimpleVectorMCPCore

@Suite("SimpleVectorApp & MCP Tests")
struct SimpleVectorAppTests {

    @Test("AppModel & VectorController editing and MCP server tools")
    @MainActor
    func testControllerAndMCP() throws {
        let model = AppModel(startServices: false, persistEnabled: false)
        let ctrl = model.controller
        #expect(ctrl.document.pages.count == 3)

        let initialCount = ctrl.currentPage.elements.count
        ctrl.stampActiveSignature()
        #expect(ctrl.currentPage.elements.count == initialCount + 1)

        ctrl.undo()
        #expect(ctrl.currentPage.elements.count == initialCount)

        // Verify MCP Server tool listing
        let mcp = SimpleVectorMCPServer(transport: { _, _, _ in
            APIResponse(status: 200, data: Data("{\"ok\":true}".utf8), contentType: "application/json")
        })
        let listResp = mcp.handle(line: "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}") ?? ""
        #expect(listResp.contains("simplevector_sign"))
        #expect(listResp.contains("simplevector_edit_text"))
    }
}
