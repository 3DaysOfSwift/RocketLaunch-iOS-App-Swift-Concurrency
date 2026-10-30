import Foundation

/// Owns only this screen's filter selections and display wording.
struct BrowseFilters {
    var search = ""
    var operatorID = ""
    var country = ""

    var query: LaunchBrowseQuery {
        LaunchBrowseQuery(search: search, operatorID: operatorID, country: country)
    }

    func launchCountLabel(for item: LaunchOperator) -> String {
        let count = item.launches.count
        return count == 1 ? String(localized: "1 launch") : String(localized: "\(count) launches")
    }

}
