import Foundation
import SimpleVectorMCPCore

let base = apiBaseURL()
let server = SimpleVectorMCPServer(transport: urlSessionTransport(base: base), apiBase: base)
server.run()
