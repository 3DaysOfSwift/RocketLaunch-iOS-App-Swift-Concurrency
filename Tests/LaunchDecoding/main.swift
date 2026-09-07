import Foundation

let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
let originalData = try Data(contentsOf: fixture)
var failures = 0
func check(_ name: String, _ body: () throws -> Void) {
    do { try body(); print("PASS: \(name)") }
    catch { failures += 1; print("FAIL: \(name): \(error)") }
}
func page(estimatedDate: [String: Any]) throws -> Data {
    var document = try JSONSerialization.jsonObject(with: originalData) as! [String: Any]
    var launches = document["result"] as! [[String: Any]]
    launches[0]["est_date"] = estimatedDate
    document["result"] = launches
    return try JSONSerialization.data(withJSONObject: document)
}
check("Original complete response still decodes") {
    let result = try JSONDecoder().decode(SearchResultsPage.self, from: originalData)
    precondition(!result.result.isEmpty)
}
check("Null day does not discard a valid launch") {
    let result = try JSONDecoder().decode(SearchResultsPage.self, from: page(estimatedDate: ["month":9,"day":NSNull(),"year":2026,"quarter":NSNull()]))
    precondition(!result.result[0].name.isEmpty)
}
check("All unknown date components decode") {
    _ = try JSONDecoder().decode(SearchResultsPage.self, from: page(estimatedDate: ["month":NSNull(),"day":NSNull(),"year":NSNull(),"quarter":NSNull()]))
}
check("Omitted estimated date components decode") {
    _ = try JSONDecoder().decode(SearchResultsPage.self, from: page(estimatedDate: [:]))
}
check("Wrong component types still report malformed data") {
    do {
        _ = try JSONDecoder().decode(SearchResultsPage.self, from: page(estimatedDate: ["month":"invalid","day":1,"year":2026]))
        throw NSError(domain:"Regression",code:1,userInfo:[NSLocalizedDescriptionKey:"Malformed month was accepted"])
    } catch DecodingError.typeMismatch { }
}
print("Failures: \(failures)")
exit(failures == 0 ? 0 : 1)
