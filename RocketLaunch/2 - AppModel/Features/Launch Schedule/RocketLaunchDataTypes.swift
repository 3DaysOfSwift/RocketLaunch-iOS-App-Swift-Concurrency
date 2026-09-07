//
//  RocketLaunchDataTypes.swift
//  RocketLaunch
//
//  Created by 3DaysOfSwift.com 06/12/2023.
//

import Foundation

struct Provider: Decodable {
    let id: Int
    let name: String
    let slug: String
}

struct Vehicle: Decodable {
    let id: Int
    let name: String
    let company_id: Int
    let slug: String
}

struct Location: Decodable {
    let id: Int
    let name: String
    let state: String?
    let statename: String?
    let country: String?
    let slug: String
}

struct Pad: Decodable {
    let id: Int
    let name: String
    let location: Location
}

struct Mission: Decodable {
    let id: Int
    let name: String
    let description: String?
}

struct LaunchDate: Decodable {
    // The API can omit or null individual components when the date is uncertain.
    let month: Int?
    let day: Int?
    let year: Int?
}

struct Tag: Decodable {
    let id: Int
    let text: String
}

struct RocketLaunch: Decodable {
    let id: Int
    let cospar_id: String?
    let sort_date: String
    let name: String
    let provider: Provider
    let vehicle: Vehicle
    let pad: Pad
    let missions:[Mission]
    let mission_description: String?
    let launch_description: String
    let win_open: String? //  ISO 8601 format
    let t0: String?
    let win_close: String? // ISO 8601 format
    let est_date: LaunchDate
    let date_str: String
    let tags:[Tag]
    let slug: String
    let weather_summary: String?
    let weather_temp: String?
    let weather_condition: String?
    let weather_wind_mph: String?
    let weather_icon: String?
    let weather_updated: String?
    let quicktext: String
    let result: Int?
    let suborbital: Bool
    let modified: String
}

struct SearchResultsPage: Decodable {
    let valid_auth: Bool
    let count: Int
    let limit: Int
    let total: Int
    let last_page: Int
    let result:[RocketLaunch]
}
